# バックエンド設計書: 運用とテスト

## Docker コマンド
初回または依存更新時は bundle install を含む build を行う。

```bash
docker-compose up --build
```

Rails service はホスト `3001` からアクセスできる。

```bash
curl http://localhost:3001/api/v1/lectures
```

Rails console は以下で開く。

```bash
docker-compose exec gatareview-back bin/rails console
```

## DB 操作
migration を実行する。

```bash
docker-compose run --rm gatareview-back bin/rails db:migrate
```

seed が必要な場合は以下を実行する。

```bash
docker-compose run --rm gatareview-back bin/rails db:seed
```

テスト DB 準備は以下を使う。

```bash
docker-compose run --rm -e RAILS_ENV=test gatareview-back bin/rails db:prepare
```

## RSpec
全体実行。

```bash
docker-compose run --rm gatareview-back bundle exec rspec
```

対象を絞る場合。

```bash
docker-compose run --rm gatareview-back bundle exec rspec spec/models/review_spec.rb
docker-compose run --rm gatareview-back bundle exec rspec spec/services/syllabus/lecture_csv_importer_spec.rb
```

現行の主な spec:
- `spec/models/review_spec.rb`
- `spec/models/site_setting_spec.rb`
- `spec/services/syllabus/campus_square_client_spec.rb`
- `spec/services/syllabus/lecture_csv_exporter_spec.rb`
- `spec/services/syllabus/lecture_csv_importer_spec.rb`

API 変更時は request spec を追加する。既存方針では endpoint 追加・変更には `spec/requests` を使う。

## 環境変数

### DB
Docker Compose は以下を参照する。

- `MYSQL_DATABASE`
- `MYSQL_PASSWORD`
- `MYSQL_USER`
- `MYSQL_HOST`
- `MYSQL_ROOT_PASSWORD`

### Google OAuth
- `GOOGLE_CLIENT_ID`: Google token の `aud` と一致させる。

バックエンドは `POST /api/v1/auth/google` で Google tokeninfo に問い合わせ、`GOOGLE_CLIENT_ID` と照合する。

### JWT
JWT encode/decode の secret はアプリ設定側に依存する。変更時は既存 session/token が無効になる可能性がある。

### reCAPTCHA
- `RECAPTCHA_SECRET_KEY`: production では必須。

挙動:
- test 環境では外部通信せず true を返す。
- development は未設定でも投稿できる。
- production は未設定または token 不正の場合、レビュー投稿に失敗する。

### 管理者
- `ADMIN_EMAILS`: カンマ区切りで複数管理者を指定する。
- `ADMIN_EMAIL`: 単一管理者指定の後方互換。

`User#admin?` は両方を読み、現在ユーザーの email と小文字比較する。

## 運用時の注意
- Google OAuth の client ID はフロントエンド NextAuth とバックエンド token 検証で同じものを使う。
- production で `RECAPTCHA_SECRET_KEY` がないとレビュー投稿は失敗する。
- 管理者 API はメールアドレス環境変数に依存するため、管理者追加・削除は環境変数変更と再起動が必要になる。
- `SiteSetting` は singleton 前提のため、DB を直接操作して複数行作らない。
- 講義 CSV import/export や Campus Square 連携を変更する場合は service spec を先に確認する。

## API 変更時の確認観点
- 認証要否:
  - 公開 API なら `skip_before_action` が正しいか。
  - 認証必須 API なら `current_user` が必ず存在する前提で安全か。
- 権限:
  - レビュー更新・削除は投稿者本人だけか。
  - 管理 API は `current_user.admin?` を通っているか。
- validation:
  - Strong Parameters に必要項目が追加されているか。
  - model validation と DB 制約が矛盾していないか。
- レスポンス:
  - フロントエンドの型、API wrapper、画面表示と一致しているか。
  - エラー時の status code が画面の想定と一致しているか。
- 性能:
  - 一覧 API で N+1 が発生していないか。
  - count、group、distinct、pagination の組み合わせで件数がずれないか。

## リリース前チェック
- `docker-compose run --rm gatareview-back bundle exec rspec`
- 代表的な API の curl 確認。
- フロントエンドからログイン、講義検索、レビュー投稿、マイページ、管理設定を確認。
- production 環境変数の不足がないことを確認。
