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
- ReviewPeriods
  - レビュー閲覧制御用の期間管理

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

## セットアップ

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

| 変数名 | 必須 | 用途 |
| --- | --- | --- |
| `MYSQL_DATABASE` | Yes | 開発 DB 名 |
| `MYSQL_USER` | Yes | 開発 DB ユーザー |
| `MYSQL_PASSWORD` | Yes | 開発 DB パスワード |
| `MYSQL_HOST` | Yes | 開発 DB ホスト |
| `JWT_SECRET_KEY` | Recommended | JWT 署名キー |
| `RAILS_SECRET_KEY_BASE` | Alternative | `JWT_SECRET_KEY` 未設定時の代替 |
| `GOOGLE_CLIENT_ID` | Feature-based | Google トークン検証 |
| `GOOGLE_CLIENT_SECRET` | Feature-based | 運用上の Google OAuth 設定保持 |
| `RECAPTCHA_SECRET_KEY` | Optional in development | レビュー投稿時の reCAPTCHA。production では実質必須 |
| `FRONTEND_URL` | Optional | production CORS 設定 |

デプロイ環境では上記に加えて、以下のような DB / Rails 環境変数を使う構成です。

- `HEROKU_DB_DATABASE_NAME`
- `HEROKU_DB_HOST`
- `HEROKU_DB_USERNAME`
- `HEROKU_DB_PASSWORD`
- `JAWSDB_URL`
- `RAILS_ENV`
- `RACK_ENV`

## 開発コマンド

```bash
bin/rails server
bin/rails console
bin/rails db:migrate
bundle exec rspec
bundle exec rubocop
```

## 重要な業務ルール

- 同一ログインユーザーは同じ授業に複数レビューを投稿できません。
- 同一ユーザーは同じレビューに複数回ありがとうできません。
- 自分のレビューにはありがとうできません。
- レビュー閲覧可否は `ReviewPeriod` とユーザーの投稿実績で判定します。
- 一部 API は未認証アクセスを許可していても、認証有無でレスポンス内容が変わります。

## テストと CI

ローカルでは最低限以下を実行してください。

```bash
bundle exec rspec
bundle exec rubocop
```

GitHub Actions では以下を実行しています。

- RSpec
- RuboCop

Workflow: `.github/workflows/rubyonrails.yml`

## 関連リポジトリ

- Frontend: `https://github.com/yu-yaba/gatareview-front`
- Backend: `https://github.com/yu-yaba/gatareview-back`
