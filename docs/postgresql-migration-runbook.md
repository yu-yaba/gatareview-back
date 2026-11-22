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

1. Aiven Console で PostgreSQL のサービスを作り、接続情報（ホスト・ポート・ユーザー・パスワード・DB 名）を確認する。CA 証明書が `config/certs/aiven-ca.pem` と同じか確認する（違えばバンドルを更新して先にデプロイする）。
2. PostgreSQL にスキーマを作る。

   ```bash
   RAILS_ENV=production DATABASE_URL='postgres://<user>@<host>:<port>/<db>?sslmode=verify-full' \
     DATABASE_SSL_CA=config/certs/aiven-ca.pem DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bin/rails db:schema:load
   ```

   パスワードは `~/.pgpass` に置き、URL やコマンド履歴に残さない。

3. リハーサルとして、データを写して確認する（手順 3〜4 と同じ）。確認できたら、切替当日にもう一度写し直す。

### 2. 書き込みの停止

```bash
heroku maintenance:on -a gatareview-back
```

### 3. データを写す

```bash
MYSQL_DEFAULTS_FILE=<MySQL の接続設定ファイル（ssl-mode=VERIFY_IDENTITY と ssl-ca を含む）> \
MYSQL_DATABASE=<MySQL の DB 名> \
PG_URL='postgres://<user>@<host>:<port>/<db>?sslmode=verify-full&sslrootcert=config/certs/aiven-ca.pem' \
  bin/copy-mysql-to-postgres
```

- 写す先にデータがあれば止まる。リハーサルのあとに当日写し直すときだけ `ALLOW_TRUNCATE=yes` を付ける（切替後には絶対に流さない）。
- PostgreSQL 側のテーブルを空にしてから、PostgreSQL 側にある列だけを写す。MySQL にだけ残っている未使用列は写さない。
- `schema_migrations` は `db:schema:load` が作ったものを使う。
- 主キーの採番は最大値の次に合わせる。

### 4. 確認

- テーブルごとの件数が MySQL と同じである。
- 行の中身が同じである。主要な列の MD5 を両方で出して比べる（日時は `YYYY-MM-DD HH:MM:SS.ffffff` にそろえる）。
- `reviews`・`lectures` の次の採番が、最大の id より大きい。

### 5. 切り替え

1. この変更を含むリリースを Heroku にデプロイする（メンテナンス中のまま）。
2. Heroku の設定を変える。

   ```bash
   heroku config:set -a gatareview-back \
     DATABASE_URL='postgres://<user>:<password>@<host>:<port>/<db>?sslmode=verify-full' \
     DATABASE_SSL_CA=/app/config/certs/aiven-ca.pem
   ```

   - Aiven の URI の `sslmode=require` のままでは起動を拒否する（証明書を検証しないため）。
   - APT buildpack（MySQL クライアント用）は不要になる。`Aptfile` を消したので、`heroku buildpacks:remove https://github.com/heroku/heroku-buildpack-apt.git -a gatareview-back` で外してから再デプロイする。
   - `MYSQL_SSL_CA` は使わなくなる。切り戻しの可能性がなくなってから消す。

3. 動作を確認する。

   ```bash
   heroku run -a gatareview-back "bin/rails runner 'puts Lecture.count, Review.count'"
   heroku run -a gatareview-back "bin/rails runner 'puts ActiveRecord::Base.connection.select_value(%q(SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()))'"
   ```

   2つ目は `true` になる。

4. `heroku maintenance:off -a gatareview-back` を実行する。授業検索（ひらがな・全角英字でも探す）、授業詳細、レビュー投稿、ブックマーク、ありがとう、ログイン、マイページを確認する。

### 切り戻し

- MySQL は 2026-12-21 まで残っている。前のリリースに戻し、`DATABASE_URL` と `MYSQL_SSL_CA` を MySQL のものに戻す。APT buildpack も戻す。
- 切り替え後に PostgreSQL へ入った書き込みは、手で MySQL に移す。

## 注意

- この変更の migration（`20261123000000_use_case_and_accent_insensitive_collation`）は PostgreSQL 専用。MySQL の本番では流さない（手順 1 の `db:schema:load` で適用済みとして記録される）。
- MySQL 時代の migration（`20261109000000_*`、`20261122000000_*`）は MySQL 専用の SQL を含むので、PostgreSQL で流し直さない。
