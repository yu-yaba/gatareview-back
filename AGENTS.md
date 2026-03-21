# Backend Agent Guide

## 概要

このリポジトリはガタレビュの Rails 7 API バックエンドです。  
主に認証、レビュー・授業・ブックマーク・ありがとう API、レビュー閲覧制御、MySQL データモデルを担当します。

## 主要ディレクトリ

- `app/controllers/api/v1/`
  API エンドポイント
- `app/controllers/concerns/`
  認証まわりの concern
- `app/models/`
  ActiveRecord モデル
- `app/services/`
  JWT、reCAPTCHA、認証補助など
- `config/routes.rb`
  API 契約の入口
- `spec/requests/`
  リクエストスペック
- `spec/factories/`
  Factory Bot

## よく使うコマンド

このリポジトリ直下で実行:

```bash
bundle install
bin/rails db:migrate
bin/verify
bin/rails console
```

統合 workspace から実行する場合:

```bash
docker-compose run --rm gatareview-back bin/rails db:migrate
docker-compose run --rm gatareview-back bin/verify
docker-compose exec gatareview-back bin/rails console
```

前提バージョン:

- Ruby `3.2.2`
- Rails `7.0.6`

## 実装上の重要ポイント

- 認証は `Authenticatable` concern と JWT で管理しています。
- 公開 API にする場合でも、既存の `authenticate_optional` でユーザー別レスポンスを返している箇所があります。`skip_before_action` の追加は慎重に行ってください。
- API 仕様を変える場合は、フロントエンドの型や表示も壊れやすいため、レスポンス形状の変更を最小限にしてください。
- レビュー閲覧制御を変更する場合は、以下をまとめて確認してください。
  - `app/controllers/api/v1/reviews_controller.rb`
  - `app/models/user.rb`
  - `app/models/site_setting.rb`
  - `app/controllers/api/v1/admin/review_access_controller.rb`
- 授業詳細レビューの閲覧可否は `SiteSetting` と `reviews_count` で決まります。lecture detail が production で 500 のときは `site_settings` migration 未実行を先に疑ってください。
- 管理者判定は `User#admin?` と `ADMIN_EMAILS` / `ADMIN_EMAIL` の環境変数で行います。
- N+1 回避を優先してください。`includes`, `joins`, `left_joins`, `group` を意図的に使っている箇所が多いです。

## 既存の業務制約

- `Review`
  - 総合評価必須
  - コメント必須
  - コメントは 30 文字以上 1000 文字以内
  - 同一ログインユーザーは同じ授業に複数レビュー不可
- `Bookmark`
  - 同一ユーザーが同じ授業を重複ブックマーク不可
- `Thank`
  - 同一ユーザーが同じレビューに重複送信不可
  - 自分のレビューには送信不可
- 管理者専用操作
  - `User#admin?` を通すこと
  - コントローラ側にメールアドレス直書きを増やさないこと

## 変更時の検証

- 変更後は最低限 `bin/verify` を実行してください。
- 以下を触った場合は request spec の追加または更新を優先してください。
  - ルーティング
  - 認証
  - レビュー投稿/編集/削除
  - ブックマーク
  - ありがとう
  - マイページ API
  - review access
- マイグレーションを追加した場合:
  - `db/schema.rb` が期待通りか確認
  - 既存データに対する互換性を確認
- review access の確認データが必要なら `bin/rails demo:review_access_seed` を使ってください。

## セキュリティ

- `.env`、`config/master.key`、実運用シークレットはコミットしないでください。
- JWT、OAuth トークン、Authorization ヘッダーの実値はログに出さないでください。
- CORS、認証スキップ、管理者権限判定を安易に緩めないでください。
- strong parameters を維持し、受け付ける項目を広げる時はフロントと合わせて確認してください。

## フロント連携で壊れやすい箇所

- `/api/v1/auth/*`
- `/api/v1/lectures`
- `/api/v1/lectures/:id/reviews`
- `/api/v1/reviews/latest`
- `/api/v1/mypage*`

これらのレスポンス形状を変更する場合は、フロント側の型定義と画面実装も同時に確認してください。
