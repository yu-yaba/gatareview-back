# バックエンド設計書: アーキテクチャ

## 目的
GataReview のバックエンドは、講義、レビュー、ユーザー、ブックマーク、ありがとう、管理設定を扱う Rails 7 API である。フロントエンド Next.js から `/api/v1` 経由で呼び出され、Google OAuth 検証と JWT 認証を提供する。

## 技術スタック
- Framework: Ruby on Rails 7 API
- Database: MySQL 8
- Test: RSpec
- Auth: Google OAuth token 検証、バックエンド JWT
- Container: Docker Compose

## レイヤ構成
- `app/controllers/api/v1/`: HTTP API の entrypoint。認証、パラメータ検証、JSON レスポンス整形を担当する。
- `app/controllers/concerns/`: Controller 横断の認証処理。
- `app/models/`: ActiveRecord model、関連、validation、JSON 整形補助。
- `app/services/`: 外部連携、JWT 認可、CSV import/export など controller から切り出す処理。
- `db/schema.rb`: 現行 DB スキーマの正。
- `spec/`: request/model/service spec と factory。

## Controller の責務
- `AuthController`: Google OAuth token 検証、ユーザー作成・更新、JWT 発行、現在ユーザー取得。
- `LecturesController`: 講義一覧、詳細、作成、人気講義、レビューなし講義。
- `ReviewsController`: 講義レビューの投稿・一覧、レビュー更新・削除、総件数、最新レビュー。
- `BookmarksController`: ログインユーザーによる講義ブックマーク作成・取得・削除。
- `ThanksController`: ログインユーザーによるレビューへのありがとう作成・取得・削除。
- `MypageController`: ログインユーザーの統計、投稿レビュー、ブックマーク、ランキング。
- `Admin::ReviewAccessController`: レビュー閲覧制限設定の取得・更新。

## 認証設計
`Authenticatable` concern が API controller に認証機能を追加する。

- `authenticate_request`:
  - `AuthorizeApiRequest.call(request.headers)` で JWT を検証する。
  - 成功時は `current_user` を設定する。
  - 失敗時は `401` と `{ error: '認証が必要です' }` を返す。
- `authenticate_optional`:
  - JWT があれば `current_user` を設定する。
  - JWT がなくてもリクエストを継続する。
- `authenticate_optional_for_create`:
  - レビュー作成用の optional auth。

公開 API は controller 側で `skip_before_action :authenticate_request` を指定する。認証必須 API は Bearer token を要求する。

## Google OAuth と JWT
ログイン時は以下の流れで認証する。

1. フロントエンドが Google `id_token` を `POST /api/v1/auth/google` に送る。
2. バックエンドが Google tokeninfo endpoint に問い合わせる。
3. `aud`, `sub`, `email`, `email_verified`, `exp`, `iss` を検証する。
4. `User.from_google_oauth` でユーザーを作成または更新する。
5. `JsonWebToken.encode(user.jwt_payload, expiration)` で JWT を発行する。
6. フロントエンドは以降の API に `Authorization: Bearer <token>` を付ける。

JWT の有効期限は remember 指定時が 30 日、通常が 7 日である。

## レビュー閲覧制限
`SiteSetting.current` の `lecture_review_restriction_enabled` で制御する。

- 無効時: 全ユーザーがレビュー全文を閲覧できる。
- 有効時:
  - 未ログインユーザーは閲覧権限なし。
  - ログイン済みでも投稿レビュー数が 0 件なら閲覧権限なし。
  - 投稿レビュー数が 1 件以上なら閲覧権限あり。
- 権限なしの場合、レビュー一覧 API は先頭レビューだけ全文を返し、それ以外の本文を先頭 30 文字に短縮する。

## 外部連携
- Google OAuth tokeninfo: Google `id_token` の検証に使う。
- reCAPTCHA: レビュー投稿時の bot 対策に使う。
- Campus Square: `app/services/syllabus/` 配下で講義 CSV import/export や syllabus 取得に使う。

## 設計上の注意
- API は `/api/v1` namespace に追加する。
- 認証が必要な endpoint は `Authenticatable` を使い、公開 endpoint は明示的に skip する。
- パラメータは Strong Parameters で許可する。
- 講義一覧やマイページの一覧系は N+1 と count の扱いに注意する。
- JSON レスポンス形状を変える場合はフロントエンドの型と docs も同時に更新する。
