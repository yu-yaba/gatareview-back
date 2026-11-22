# MySQL → PostgreSQL 切替ランブック

本番 DB を Aiven for MySQL（無料プラン。2026-12-21 に終了）から Aiven for PostgreSQL に移す手順。
アプリの PostgreSQL 対応（`pg` gem、`config/database.yml`、照合順序 `ci_ai`）は、このランブックと同じ変更で入っている。

## 前提

- `20261122000000_change_reviews_lecture_id_to_bigint` を MySQL の本番に適用済みである（`reviews.lecture_id` が bigint）。
- Aiven for PostgreSQL のサービスが **PostgreSQL 18** で作成済みである。授業検索は非決定的な照合順序 `ci_ai` で `LIKE` を使うため、18 未満では検索が失敗する。
- 手元に `mysql` と `psql`（18）のクライアントがある。
- 作業前の MySQL のダンプを、リポジトリの外に保存済みである。

## 変わる挙動

- 授業名・教員名・学部・メールアドレスの比較は、MySQL の `utf8mb4_0900_ai_ci` と同じく、大文字小文字・全角半角・ひらがなカタカナ・濁点の有無を区別しない（ICU `und-u-ks-level1`）。
- 部分一致検索は MySQL より少し広くヒットすることがある。例えば `II` で `Ⅱ` を含む授業も見つかる。本番データのコピーで200語ほどを比べ、MySQL で見つかった授業が見つからなくなる例はなかった。
- レビューの JSON の `lecture_id` は数値になる（前の PR から）。
- マイページの平均評価の丸めは、四捨五入（PostgreSQL の numeric の `round`）になる。

## 手順

### 1. 事前準備（停止不要）

0. Aiven Console で `avnadmin` のパスワードを変更する（接続情報がほかに漏れていないとはっきりしない場合は必ず）。
1. Aiven Console で PostgreSQL のサービスを作り、接続情報（ホスト・ポート・ユーザー・パスワード・DB 名）を確認する。CA 証明書が `config/certs/aiven-ca.pem` と同じか確認する（違えばバンドルを更新して先にデプロイする）。
2. PostgreSQL にスキーマを作る。

   ```bash
   RAILS_ENV=production DATABASE_URL='postgres://<user>@<host>:<port>/<db>?sslmode=verify-full' \
     DATABASE_SSL_CA=config/certs/aiven-ca.pem DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bin/rails db:schema:load
   ```

   パスワードは `~/.pgpass` に置き、URL やコマンド履歴に残さない。

3. アプリ用の最小権限ロール `gatareview_runtime` を作る（MySQL と同じく、アプリは権限を絞ったユーザーでつなぐ）。

   ```bash
   ADMIN_PG_URL='postgres://avnadmin@<host>:<port>/<db>?sslmode=verify-full&sslrootcert=config/certs/aiven-ca.pem' \
   RUNTIME_URL_FILE=~/.gatareview-postgres-runtime-url \
     bin/create-postgres-runtime-role
   ```

   - 付く権限は、全テーブルの読み書き（SELECT/INSERT/UPDATE/DELETE）と、シーケンスの使用だけ。テーブルの作成・変更・削除、TRUNCATE はできない。
   - 管理者があとから作るテーブルにも同じ権限が付く。そのため、`db:schema:load` でテーブルを作り直しても権限は残る。
   - パスワードは手元で作り、サーバーにはハッシュだけを送る。アプリ用の接続先（パスワード入り）は `RUNTIME_URL_FILE` に権限 600 で書かれる。
   - もう一度流すと、パスワードを新しくして権限をそろえ直す（パスワードの変更にも使える）。

4. リハーサルとして、データを写して確認する（手順 3〜4 と同じ）。確認できたら、切替当日にもう一度写し直す。

### 2. 書き込みの停止

1. **切替前のリリース番号を控える**（切り戻しで使う）。`heroku releases -a gatareview-back -n 1` で確認できる（例: `v176`）。
2. **Heroku Scheduler のジョブを止める。** メンテナンスモードでも Scheduler のジョブと one-off dyno は動く。Dashboard → Resources → Heroku Scheduler で、ジョブを一時停止するか、控えてから消す。
3. `heroku ps -a gatareview-back` で、one-off dyno（`run.*` / `scheduler.*`）が動いていないことを確かめる。
4. メンテナンスモードにする。

   ```bash
   heroku maintenance:on -a gatareview-back
   ```

### 3. データを写す

```bash
ALLOW_TRUNCATE=yes \
MYSQL_DEFAULTS_FILE=<MySQL の接続設定ファイル（ssl-mode=VERIFY_IDENTITY と ssl-ca を含む）> \
MYSQL_DATABASE=<MySQL の DB 名> \
PG_URL='postgres://avnadmin@<host>:<port>/<db>?sslmode=verify-full&sslrootcert=config/certs/aiven-ca.pem' \
  bin/copy-mysql-to-postgres
```

- TRUNCATE を使うので、管理者ユーザー（`avnadmin`）で流す。アプリ用ロールではできない。
- 写す先にデータがあれば止まる。`ALLOW_TRUNCATE=yes` はリハーサルのデータを捨てて写し直すときだけ付ける（**切替後には絶対に流さない**）。
- 先に MySQL の全テーブルを書き出してから、PostgreSQL 側を1つのトランザクションで入れ替える。途中で失敗すれば PostgreSQL は元のまま残るので、原因を直してもう一度流す。
- NUL 文字を含むデータがあれば、何も変えずに止まる（PostgreSQL は保存できない）。
- PostgreSQL 側にある列だけを写す。MySQL にだけ残っている未使用列は写さない。
- `schema_migrations` は `db:schema:load` が作ったものを使う。
- 主キーの採番は最大値の次に合わせる。

### 4. 確認

- テーブルごとの件数が MySQL と同じである。
- 行の中身が同じである。主要な列の MD5 を両方で出して比べる（日時は `YYYY-MM-DD HH:MM:SS.ffffff` にそろえる）。
- `reviews`・`lectures` の次の採番が、最大の id より大きい。
- **1つでも合わなければ切り替えない。** 手順 3 からやり直すか、メンテナンスを解除して中止する。

### 5. 切り替え

順番が大事。この順で行う（メンテナンス中のまま）。

1. APT buildpack を外す（`Aptfile` を消したので、残したままだとビルドが失敗する）。

   ```bash
   heroku buildpacks:remove https://github.com/heroku/heroku-buildpack-apt.git -a gatareview-back
   ```

2. Heroku の設定を変える。**値が画面に出ないように出力を捨てる**（`config:set` は設定した値を表示する）。

   ```bash
   heroku config:set -a gatareview-back \
     DATABASE_URL="$(cat ~/.gatareview-postgres-runtime-url)" \
     DATABASE_SSL_CA=/app/config/certs/aiven-ca.pem >/dev/null
   heroku config -a gatareview-back --json | python3 -c "import sys,json; print(sorted(json.load(sys.stdin)))"
   ```

   - `DATABASE_URL` はアプリ用ロール `gatareview_runtime` の接続先にする（`avnadmin` にしない）。`bin/create-postgres-runtime-role` が書いたファイルの URL は `sslmode=verify-full` だけを含むので、そのまま使える。
   - Aiven の URI の `sslmode=require` のままでは起動を拒否する（証明書を検証しないため）。
   - **この時点でできるリリースは起動しない（想定どおり）。** 古いコード（mysql2 だけ）に PostgreSQL の URL を渡すことになるため。メンテナンス中なので利用者には見えない。切り戻しでこのリリースを選ばないこと。
   - `MYSQL_SSL_CA` は使わなくなる。切り戻しの可能性がなくなってから消す。

3. PR #78 を `main` にマージする。GitHub 連携の自動デプロイで、ビルドとリリースが行われる。`heroku releases -a gatareview-back` で `Deploy <マージコミット>` が出るまで待つ。
   - 数分たってもデプロイされなければ、Dashboard → Deploy の「Deploy Branch」で `main` を手動でデプロイする。
   - **ビルドが失敗したら**、リリースは作られない。切り替えを中止して、下の「切り戻し」の手順 4 以降を行う（データは MySQL のままなので写し戻しは不要）。

4. 動作を確認する（メンテナンス中は Web からは見えないので、one-off dyno で確かめる）。

   ```bash
   heroku run -a gatareview-back "bin/rails runner 'puts Lecture.count, Review.count'"
   heroku run -a gatareview-back "bin/rails runner 'puts ActiveRecord::Base.connection.select_value(%q(SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()))'"
   ```

   2つ目は `true` になる。終わったら、手元で開いた `avnadmin` の接続をすべて閉じる（無料プランの接続数は 20 で、うち 3 は管理用に予約されている。アプリは最大 10 使う）。

5. `heroku maintenance:off -a gatareview-back` を実行する。すぐに次を確認する: 授業検索（ひらがな・全角英字でも探す）、授業詳細、レビュー投稿、ブックマーク、ありがとう、ログイン、マイページ。`heroku logs --tail` で 5xx が出ていないかも見る。
6. 止めた Heroku Scheduler のジョブを元に戻す。

### 切り戻し

MySQL は 2026-12-21 まで残っている（その日に Aiven が停止し、データも消える）。それまでなら次の手順で戻せる。

1. `heroku maintenance:on -a gatareview-back` を実行して、書き込みを止める。Scheduler のジョブも止める。
2. 念のため、MySQL と PostgreSQL の両方のダンプを取り、リポジトリの外に保存する。
3. 切替後に PostgreSQL へ入った書き込み（レビュー・ブックマーク・ありがとう・新規ユーザー、更新と削除）を MySQL に写し戻す（切替後にまったく書き込みがなかった場合や、ビルド失敗で中止した場合は不要）。

   ```bash
   ALLOW_OVERWRITE_MYSQL=yes \
   MYSQL_DEFAULTS_FILE=<MySQL の接続設定ファイル（ssl-mode=VERIFY_IDENTITY と ssl-ca を含む）> \
   MYSQL_DATABASE=<MySQL の DB 名> \
   PG_URL='postgres://<user>@<host>:<port>/<db>?sslmode=verify-full&sslrootcert=config/certs/aiven-ca.pem' \
     bin/copy-postgres-to-mysql
   ```

   - MySQL のアプリ用テーブルを、PostgreSQL の内容で丸ごと置き換える。1つのトランザクションで行うので、途中で失敗すれば MySQL は元のまま残る。
   - MySQL の `users` / `lectures` / `reviews` に PostgreSQL より新しい id があれば止まる。向きを取り違えて、MySQL にしかない書き込みを消すのを防ぐため。
   - 本番の MySQL ユーザー `gatareview_runtime` には DELETE / INSERT の権限があるので、`heroku config:get DATABASE_URL` の値（切り戻し前の設定は `heroku releases:info <控えた番号>` の時点のもの）から接続設定を作れる。
   - 終わったら、手順 4 と同じ方法で両方の中身が一致することを確かめる。
4. **控えておいた切替前のリリース番号を指定して**戻す（番号を省くと、ひとつ前の「起動しないリリース」に戻ってしまう）。

   ```bash
   heroku releases:rollback v176 -a gatareview-back   # 例。手順 2-1 で控えた番号
   heroku buildpacks:add --index 1 https://github.com/heroku/heroku-buildpack-apt.git -a gatareview-back
   ```

   - コードと設定（`DATABASE_URL`、`MYSQL_SSL_CA` など）がまとめて戻る。戻した先は APT buildpack でビルドしたものなので、そのまま動く。buildpack は次のビルドに備えて戻す。
   - **`main` には PostgreSQL 版のコードが残っている。** このまま `main` にマージすると自動デプロイで壊れるので、PR #78 を revert するか、Dashboard → Deploy で自動デプロイを一時的に止める。
5. `heroku maintenance:off -a gatareview-back` を実行して、動作を確認する。Scheduler のジョブを元に戻す。

## 注意

- 切替後の migration は、`heroku run bin/rails db:migrate` では流せない（アプリ用ロールにテーブルを変える権限がない。MySQL のときと同じ）。メンテナンスモードの間に、手元から `avnadmin` の接続先で `RAILS_ENV=production bin/rails db:migrate` を流す。

- この変更の migration（`20261123000000_use_case_and_accent_insensitive_collation`）は PostgreSQL 専用。MySQL の本番では流さない（手順 1 の `db:schema:load` で適用済みとして記録される）。
- MySQL 時代の migration（`20261109000000_*`、`20261122000000_*`）は MySQL 専用の SQL を含むので、PostgreSQL で流し直さない。
