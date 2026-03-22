# Aiven for MySQL Free 移行ランブック

## 目的

- backend は Heroku 上で動かし続ける
- production DB を JawsDB から Aiven for MySQL Free に移す
- frontend は現在の backend URL を使い続ける
- Heroku の環境変数切替だけでロールバックできる状態にする

## 現在構成と移行後構成

- 現在: `Heroku web + JawsDB`
- 移行後: `Heroku web + Aiven for MySQL Free`
- backend の URL を変えない前提なら、frontend の Vercel 環境変数変更は不要

## 必要なコード状態

- production の DB 設定は `DATABASE_URL` を優先し、未設定時は `JAWSDB_URL` にフォールバックする
- このリポジトリでは、その挙動を [config/database.yml](/Users/kawaiyuya/Desktop/gatareview/gatareview-back/config/database.yml) に実装済み

## 前提条件

- Aiven の MySQL サービスが作成済みである
- Aiven コンソールから接続情報を取得できる
- `DATABASE_URL` 対応コードを Heroku に先に deploy してある
- Aiven 切替後もしばらくは JawsDB を残しておく

## 環境変数

- `JAWSDB_URL` はロールバック用にそのまま残す
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

Heroku の `DATABASE_URL` には、Aiven コンソールが出す URI をそのまま使う。

## リハーサル

### 1. 現在の Heroku DB URL を確認する

```bash
heroku config:get JAWSDB_URL -a gatareview-back
```

### 2. JawsDB の dump をローカルに取得する

```bash
mkdir -p tmp

mysqldump \
  --single-transaction \
  --set-gtid-purged=OFF \
  --column-statistics=0 \
  --default-character-set=utf8mb4 \
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
DATABASE_URL='<AIVEN_DATABASE_URL>' bin/rails runner 'puts ActiveRecord::Base.connection.select_value("SELECT 1")'
DATABASE_URL='<AIVEN_DATABASE_URL>' bin/rails runner 'puts Lecture.count'
DATABASE_URL='<AIVEN_DATABASE_URL>' bin/rails runner 'puts Review.count'
```

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
```

### 5. dyno を再起動する

```bash
heroku restart -a gatareview-back
```

### 6. 読み取り系のスモークチェックを行う

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
heroku config:unset DATABASE_URL -a gatareview-back
heroku restart -a gatareview-back
heroku maintenance:off -a gatareview-back
```

`JAWSDB_URL` は残してあるので、再起動後は自動で元の DB に戻る。

## 切替後

- 数日は JawsDB を残して退避先として保持する
- backend の URL を変えない限り、Vercel の `NEXT_PUBLIC_ENV` は変更しない
- Aiven Free が不安定なら、別移行ではなく同じ Aiven サービスのプラン変更を優先する
