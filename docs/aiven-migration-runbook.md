# Aiven for MySQL Free 移行ランブック

## 目的

- backend は Heroku 上で動かし続ける
- production DB を JawsDB から Aiven for MySQL Free に移す
- frontend は現在の backend URL を使い続ける
- 旧DBの接続先とCA証明書を保管し、両方を戻せる状態にする

## 現在構成と移行後構成

- 現在: `Heroku web + JawsDB`
- 移行後: `Heroku web + Aiven for MySQL Free`
- backend の URL を変えない前提なら、frontend の Vercel 環境変数変更は不要

## 必要なコード状態

- production の DB 設定は `DATABASE_URL` を使う。`JAWSDB_URL` への自動フォールバックはない
- [config/database.yml](/Users/kawaiyuya/Desktop/gatareview/gatareview-back/config/database.yml) で本番の証明書・ホスト名検証を指定する。Aiven独自のCAを使う場合は、`MYSQL_SSL_CA` に読み取り可能なCA証明書のパスを設定する。未設定時はシステムのCAを使う
- AivenのURIに含まれる `ssl-mode=REQUIRED` はmysql2の `ssl_mode` とは別のキーなので、URIを貼るだけでTLSが有効になるとは判断しない。本番設定で検証を明示し、接続後に暗号化を確かめる

## 前提条件

- Aiven の MySQL サービスが作成済みである
- Aiven コンソールから接続情報を取得できる
- `DATABASE_URL` 対応コードを Heroku に先に deploy してある
- Aiven独自のCAを使う場合は、証明書が実行環境から読み取れる場所にあり、`MYSQL_SSL_CA` がそのパスを指している。システムのCAで検証できるサービスの場合も、後述の接続検証を行う
- Aiven 切替後もしばらくは JawsDB を残しておく

## 環境変数

- 旧DBの `DATABASE_URL` とCA証明書のパスを安全な場所に保管する。値をログやドキュメントに転記しない
- `DATABASE_URL` は切替時にだけ Heroku へ追加する
- `FRONTEND_URL`、`JWT_SECRET_KEY`、`GOOGLE_CLIENT_ID`、`GOOGLE_CLIENT_SECRET`、`RECAPTCHA_SECRET_KEY` は変更しない

## Aiven 接続情報

Aiven コンソールから以下を控える。

- `AIVEN_DB_HOST`
- `AIVEN_DB_PORT`
- `AIVEN_DB_NAME`
- `AIVEN_DB_USER`
- `AIVEN_DB_PASSWORD`
- `AIVEN_DATABASE_URL`
- AivenコンソールからダウンロードしたCA証明書

Herokuの `DATABASE_URL` にはAivenの接続先を設定し、`MYSQL_SSL_CA` にはコンテナ内のCA証明書のパスを設定する。手元のファイルパスを設定するだけでは、Herokuのコンテナからは読み取れない。CA証明書をイメージに同梱する場合、公開用のCA証明書だけを扱い、Railsの復号鍵や秘密鍵を同梱しない。

本番の接続先・CA証明書は今回のローカル検証では確認していない。以下の実接続確認は本番反映前に運用者が行う。CAの更新時にも、証明書と接続の検証を繰り返す。

## リハーサル

### 1. 現在の接続先とCA証明書を保管する

Herokuの設定から現在のDB接続先を確認し、URLと対応するCA証明書を安全に保管する。シェルの履歴、共有ログ、監査レポートには秘密値を出力しない。

### 2. JawsDB の dump をローカルに取得する

```bash
mkdir -p tmp

mysqldump \
  --single-transaction \
  --set-gtid-purged=OFF \
  --column-statistics=0 \
  --default-character-set=utf8mb4 \
  --ssl-mode=VERIFY_IDENTITY \
  --ssl-ca=<JAWSDB_CA_CERTIFICATE> \
  -h <JAWSDB_HOST> \
  -P <JAWSDB_PORT> \
  -u <JAWSDB_USER> \
  -p \
  <JAWSDB_DATABASE> > tmp/gatareview_production.sql
```

### 3. Aiven に restore する

```bash
mysql \
  --default-character-set=utf8mb4 \
  --ssl-mode=VERIFY_IDENTITY \
  --ssl-ca=<AIVEN_CA_CERTIFICATE> \
  -h <AIVEN_DB_HOST> \
  -P <AIVEN_DB_PORT> \
  -u <AIVEN_DB_USER> \
  -p \
  <AIVEN_DB_NAME> < tmp/gatareview_production.sql
```

### 4. テーブル件数を比較する

最低限、以下を確認する。

- `lectures`
- `reviews`
- `users`
- `bookmarks`
- `thanks`

### 5. backend が Aiven から読めることを確認する

一時的に `DATABASE_URL` を差し込んで、backend コードから読み取り確認を行う。

```bash
RAILS_ENV=production DATABASE_URL='<AIVEN_DATABASE_URL>' MYSQL_SSL_CA='<AIVEN_CA_CERTIFICATE>' bin/rails runner 'puts ActiveRecord::Base.connection.select_value("SELECT 1")'
RAILS_ENV=production DATABASE_URL='<AIVEN_DATABASE_URL>' MYSQL_SSL_CA='<AIVEN_CA_CERTIFICATE>' bin/rails runner 'puts Lecture.count'
RAILS_ENV=production DATABASE_URL='<AIVEN_DATABASE_URL>' MYSQL_SSL_CA='<AIVEN_CA_CERTIFICATE>' bin/rails runner 'puts Review.count'
```

本番と同じ設定で接続し、暗号化が有効か確認する。

```bash
RAILS_ENV=production DATABASE_URL='<AIVEN_DATABASE_URL>' MYSQL_SSL_CA='<AIVEN_CA_CERTIFICATE>' bin/rails runner - <<'RUBY'
cipher = ActiveRecord::Base.connection.select_rows("SHOW SESSION STATUS LIKE 'Ssl_cipher'").first&.last
abort 'MySQL TLS is not active' if cipher.blank?
puts 'MySQL TLS is active'
RUBY
```

`Ssl_cipher` が空なら反映を止める。CAが誤っている場合やホスト名が一致しない場合に接続が拒否されることも、テスト環境で確認する。`SELECT 1` の成功だけでは暗号化や証明書検証の証拠にならない。

## 本番切替

### 1. maintenance mode を有効にする

```bash
heroku maintenance:on -a gatareview-back
```

### 2. 最終版の JawsDB dump を取得する

リハーサルと同じコマンドで、切替直前の dump を取り直す。

### 3. 最終 dump を Aiven に再投入する

切替対象の Aiven DB に対して、最終 dump を restore する。

### 4. Heroku に `DATABASE_URL` を設定する

```bash
heroku config:set DATABASE_URL='<AIVEN_DATABASE_URL>' -a gatareview-back
heroku config:set MYSQL_SSL_CA='<CA_PATH_IN_CONTAINER>' -a gatareview-back
```

### 5. dyno を再起動する

```bash
heroku restart -a gatareview-back
```

### 6. 読み取り系のスモークチェックを行う

リハーサルと同じ `Ssl_cipher` の確認をHerokuの実行環境でも行い、TLSが有効であることを確認する。

以下を確認する。

- `GET /api/v1/lectures/:id`
- `GET /api/v1/lectures/:id/reviews`
- `GET /api/v1/reviews/latest`
- frontend からの Google ログイン導線

### 7. データを残さずに書き込み確認を行う

transaction 内でレビューを作成し、最後に rollback する。

```bash
heroku run -a gatareview-back "bin/rails runner '
ActiveRecord::Base.transaction do
  lecture = Lecture.joins(:reviews).first || Lecture.first
  Review.create!(
    lecture: lecture,
    rating: 5,
    content: \"Aiven cutover validation review content that is long enough to pass validation.\"
  )
  raise ActiveRecord::Rollback
end
puts :ok
'"
```

これで、実データを増やさずに `INSERT` 可否だけ確認できる。

### 8. maintenance mode を解除する

```bash
heroku maintenance:off -a gatareview-back
```

## ロールバック

切替後の確認で問題があれば、以下で JawsDB に戻す。

```bash
heroku maintenance:on -a gatareview-back
heroku config:set DATABASE_URL='<PREVIOUS_DATABASE_URL>' MYSQL_SSL_CA='<PREVIOUS_CA_PATH_IN_CONTAINER>' -a gatareview-back
heroku restart -a gatareview-back
```

`DATABASE_URL` を削除しても `JAWSDB_URL` には戻らない。旧DBの接続先とCA設定を明示的に戻し、接続、`Ssl_cipher`、APIの応答を確認してからmaintenance modeを解除する。切替後にAivenへ書き込んだデータは旧DBへ自動反映されないため、ロールバック前に差分を確認する。

```bash
heroku maintenance:off -a gatareview-back
```

## 切替後

- 数日は JawsDB を残して退避先として保持する
- backend の URL を変えない限り、Vercel の `NEXT_PUBLIC_ENV` は変更しない
- Aiven Free が不安定なら、別移行ではなく同じ Aiven サービスのプラン変更を優先する
