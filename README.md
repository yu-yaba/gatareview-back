# ガタレビュ Backend

新潟大学向け授業レビューサービス「ガタレビュ」の Rails 7 API バックエンドです。  
認証、授業・レビュー・ブックマーク・ありがとう・マイページ API、およびレビュー閲覧制御を担当します。

- Production site: `https://www.gatareview.com`
- Frontend repo: `https://github.com/yu-yaba/gatareview-front`
- Agent guide: [`AGENTS.md`](./AGENTS.md)

## 主な API 領域

- Auth
  - Google OAuth 連携
  - 現在ユーザー取得
  - ログアウト
- Lectures
  - 授業検索
  - 授業詳細
  - 人気授業 / レビュー未投稿授業
- Reviews
  - 一覧取得
  - 投稿
  - 編集
  - 削除
  - 総件数 / 最新レビュー
- Bookmarks
  - 追加 / 解除 / 状態取得
- Thanks
  - 追加 / 解除 / 状態取得
- Mypage
  - 統計情報
  - 投稿レビュー一覧
  - ブックマーク一覧
- Admin Review Access
  - 授業詳細レビュー閲覧制限の手動 ON / OFF

## 技術スタック

| 領域 | 技術 |
| --- | --- |
| Language | Ruby 3.2.2 |
| Framework | Rails 7.0.6 |
| API | Rails API mode |
| Database | MySQL |
| Auth | JWT, Google OAuth |
| Test | RSpec, Factory Bot |
| Lint | RuboCop |

## ディレクトリ構成

```text
app/controllers/api/v1/   API エンドポイント
app/controllers/concerns/ 認証 concern
app/models/               ActiveRecord モデル
app/services/             JWT、reCAPTCHA、認証補助
config/routes.rb          API ルーティング
spec/requests/            request spec
spec/factories/           Factory Bot
```

## 前提

- Ruby 3.2.2
- Bundler
- MySQL 8 系を推奨
- 実運用と同じ確認をしたい場合は Docker 実行を推奨

## セットアップ

チームの標準導線は Docker です。ローカル Ruby 直実行も可能ですが、検証は Docker を正とします。

1. 依存関係をインストール

```bash
bundle install
```

2. `.env` を作成

最小構成の例:

```env
MYSQL_DATABASE=gatareview_development
MYSQL_USER=root
MYSQL_PASSWORD=your_password
MYSQL_HOST=127.0.0.1

JWT_SECRET_KEY=your_jwt_secret

# Optional in development / required by feature
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
RECAPTCHA_SECRET_KEY=
FRONTEND_URL=http://localhost:3000
```

3. DB を作成してマイグレーション

```bash
bin/rails db:create
bin/rails db:migrate
```

4. サーバー起動

```bash
bin/rails server
```

5. API は以下で待ち受けます

```text
http://localhost:3000
```

フロントエンドから利用する場合は、別途フロント側で `NEXT_PUBLIC_ENV` を backend の URL に合わせて設定してください。

## 環境変数

| 変数名 | 必須 | 用途 | 本番例 |
| --- | --- | --- | --- |
| `MYSQL_DATABASE` | Yes | 開発 DB 名 | Heroku アドオン値 |
| `MYSQL_USER` | Yes | 開発 DB ユーザー | Heroku アドオン値 |
| `MYSQL_PASSWORD` | Yes | 開発 DB パスワード | Heroku アドオン値 |
| `MYSQL_HOST` | Yes | 開発 DB ホスト | Heroku アドオン値 |
| `JWT_SECRET_KEY` | Recommended | JWT 署名キー | ランダムな長い文字列 |
| `RAILS_SECRET_KEY_BASE` | Alternative | `JWT_SECRET_KEY` 未設定時の代替 | Rails secret |
| `GOOGLE_CLIENT_ID` | Feature-based | Google トークン検証 | Google Cloud Console の値 |
| `GOOGLE_CLIENT_SECRET` | Feature-based | 運用上の Google OAuth 設定保持 | Google Cloud Console の値 |
| `RECAPTCHA_SECRET_KEY` | Optional in development | レビュー投稿時の reCAPTCHA。production では実質必須 | reCAPTCHA secret |
| `FRONTEND_URL` | Optional | production CORS 設定 | `https://www.gatareview.com` |
| `ADMIN_EMAILS` | Feature-based | 管理画面へ入れるメールアドレス | `admin@example.com,ops@example.com` |

デプロイ環境では上記に加えて、以下のような DB / Rails 環境変数を使う構成です。

- `HEROKU_DB_DATABASE_NAME`
- `HEROKU_DB_HOST`
- `HEROKU_DB_USERNAME`
- `HEROKU_DB_PASSWORD`
- `JAWSDB_URL`
- `RAILS_ENV`
- `RACK_ENV`

`site_settings` は環境変数ではなく DB テーブルです。review access を本番で使う場合は env 追加とは別に migration 実行が必要です。

## 開発コマンド

```bash
bin/rails server
bin/rails console
bin/rails db:migrate
bundle exec rspec
bundle exec rubocop
bin/verify
```

Docker 前提の確認導線:

```bash
docker compose run --rm gatareview-back bin/rails db:migrate
docker compose run --rm gatareview-back bin/verify
```

## 授業 CSV 自動生成

DB 登録は行わず、シラバス検索から seed 互換の CSV だけを生成します。

```bash
bin/rails lectures:export_csv YEAR=2026
```

任意の出力先を使う場合:

```bash
bin/rails lectures:export_csv YEAR=2026 OUTPUT_DIR=/path/to/output
```

## 授業 CSV の手動投入

`db:seed` は本番講義データの投入には使いません。対象 CSV を明示指定して取り込みます。

```bash
bin/rails lectures:import_csv CSV_PATH=lectureData_2026.csv
```

絶対パスを使う場合:

```bash
bin/rails lectures:import_csv CSV_PATH=/path/to/lectureData_2026.csv
```

## 件数確認

投入前後の確認には以下を使います。

全件数と faculty 別件数:

```bash
bin/rails lectures:count
```

特定 faculty の件数:

```bash
bin/rails lectures:count FACULTY='E:経済科学部'
```

## Heroku での本番投入手順

1. `main` にマージして Heroku へ deploy する
2. deploy 後に投入前件数を確認する
3. CSV を明示指定して手動 import する
4. 投入後件数を再確認する

例:

```bash
heroku run bin/rails lectures:count -a <APP_NAME>
heroku run bin/rails lectures:count FACULTY='E:経済科学部' -a <APP_NAME>
heroku run bin/rails lectures:import_csv CSV_PATH=lectureData_2026.csv -a <APP_NAME>
heroku run bin/rails lectures:count -a <APP_NAME>
heroku run bin/rails lectures:count FACULTY='E:経済科学部' -a <APP_NAME>
```

補足:

- `db:seed` は production では講義データを投入しません
- 開発用のテスト講義は production では作成されません

## 運用ドキュメント

- [`docs/annual-lecture-import-plan.md`](./docs/annual-lecture-import-plan.md)

## 重要な業務ルール

- 同一ログインユーザーは同じ授業に複数レビューを投稿できません。
- 同一ユーザーは同じレビューに複数回ありがとうできません。
- 自分のレビューにはありがとうできません。
- 授業詳細レビューの閲覧可否は `SiteSetting` の単一スイッチとユーザーの `reviews_count` で判定します。
- 一部 API は未認証アクセスを許可していても、認証有無でレスポンス内容が変わります。

## テストと CI

ローカルでは最低限以下を実行してください。

```bash
bin/verify
```

GitHub Actions では以下を実行しています。

- RSpec
- RuboCop

Workflow: `.github/workflows/rubyonrails.yml`

## デモデータ

review access の確認用データは以下で投入できます。

```bash
docker compose run --rm gatareview-back bin/rails demo:review_access_seed
```

投入されるもの:

- review access 用 `SiteSetting`
- レビュー 0 件 / 1 件 / 2 件の授業
- `reviews_count = 0` のユーザー
- `reviews_count >= 1` のユーザー
- 任意で管理者として使えるダミーユーザー

実際の管理画面ログインは `ADMIN_EMAILS` に設定した実メールアドレスで行ってください。

## デプロイ前確認

Heroku 反映前の確認手順は [`docs/deploy-checklist.md`](./docs/deploy-checklist.md) にまとめています。  
review access の変更では `ADMIN_EMAILS` 追加と `db:migrate` の両方を忘れないでください。

## 関連リポジトリ

- Frontend: `https://github.com/yu-yaba/gatareview-front`
- Backend: `https://github.com/yu-yaba/gatareview-back`
