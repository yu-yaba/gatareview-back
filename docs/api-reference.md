# バックエンド設計書: API リファレンス

## 共通
- Base path: `/api/v1`
- JSON API として利用する。
- 認証必須 API は `Authorization: Bearer <JWT>` を要求する。
- validation error は主に `422 Unprocessable Entity` を返す。
- 権限不足は `403 Forbidden`、未認証は `401 Unauthorized` を返す。

## 認証

### `POST /auth/google`
- 認証: 不要
- 目的: Google `id_token` を検証し、バックエンド JWT を発行する。
- 主な body:
  - `token`: Google `id_token`
  - `remember`: remember me 指定
- 主な response:
  - `message`
  - `token`
  - `user`: `id`, `email`, `name`, `avatar_url`, `admin`

### `GET /auth/me`
- 認証: 任意。ただし `current_user` がない場合は `401`
- 目的: 現在ユーザーを返す。
- 主な response:
  - `user`: `id`, `email`, `name`, `avatar_url`, `reviews_count`, `admin`

### `POST /auth/logout`
- 認証: 必須
- 目的: ログアウト成功メッセージを返す。JWT は stateless なので破棄はフロントエンド側で行う。

## 講義

### `GET /lectures`
- 認証: 不要
- 目的: 講義一覧を検索、絞り込み、並び替え、ページングして返す。
- Query:
  - `page`: 1 始まり。未指定時 1
  - `search`: 講義名または教員名の LIKE 検索
  - `faculty`: 学部完全一致
  - `sort`: `newest`, `highestRating`, `mostReviewed`
  - `period_year`, `period_term`, `textbook`, `attendance`, `grading_type`, `content_difficulty`, `content_quality`
- Response:
  - `lectures`: 講義配列。各要素に `avg_rating`, `review_count` を含む。
  - `pagination`: `current_page`, `total_pages`, `total_count`, `per_page`

### `GET /lectures/:id`
- 認証: 不要
- 目的: 講義詳細を返す。
- Response:
  - 講義基本項目
  - `avg_rating`
  - `review_count`

### `POST /lectures`
- 認証: 管理者必須
- 目的: 講義を作成する。
- Body:
  - `lecture.title`
  - `lecture.lecturer`
  - `lecture.faculty`

### `GET /lectures/popular`
- 認証: 不要
- 目的: レビュー数が多い講義を最大 4 件返す。

### `GET /lectures/no_reviews`
- 認証: 不要
- 目的: レビューがない講義を最大 4 件ランダムな offset で返す。

## レビュー

### `GET /lectures/:lecture_id/reviews`
- 認証: 任意
- 目的: 講義に紐づくレビュー一覧と閲覧権限状態を返す。
- Response:
  - `reviews`: レビュー配列。`user`, `user_id`, `thanks_count` を含む。
  - `access`: `restriction_enabled`, `access_granted`
- 注意:
  - レビュー閲覧制限が有効で権限がない場合、先頭レビュー以外の本文は先頭 30 文字のみ返る。

### `POST /lectures/:lecture_id/reviews`
- 認証: 任意
- 目的: レビューを作成する。ログイン済みならユーザーに紐付け、未ログインなら匿名投稿にする。
- Body:
  - `token`: reCAPTCHA token
  - `review.rating`
  - `review.content`
  - `review.period_year`
  - `review.period_term`
  - `review.textbook`
  - `review.attendance`
  - `review.grading_type`
  - `review.content_difficulty`
  - `review.content_quality`
- 注意:
  - production では `RECAPTCHA_SECRET_KEY` が必須。
  - ログインユーザーは同一講義に複数レビューを投稿できない。

### `PATCH /reviews/:id`
- 認証: 必須
- 目的: 自分のレビューを更新する。
- Body: 作成時と同じ `review` 項目。
- 権限: 投稿者本人のみ。

### `DELETE /reviews/:id`
- 認証: 必須
- 目的: 自分のレビューを削除する。
- 権限: 投稿者本人のみ。

### `GET /reviews/total`
- 認証: 不要
- 目的: 全レビュー数を返す。
- Response: `{ "count": number }`

### `GET /reviews/latest`
- 認証: 任意
- 目的: 最新レビューを最大 4 件返す。
- Response:
  - 配列。各要素に `id`, `rating`, `created_at`, `content`, `lecture`, `user` を含む。

## ブックマーク

### `POST /lectures/:lecture_id/bookmarks`
- 認証: 必須
- 目的: 現在ユーザーの講義ブックマークを作成する。

### `GET /lectures/:lecture_id/bookmarks`
- 認証: 必須
- 目的: 現在ユーザーが対象講義をブックマーク済みか返す。
- Response: `{ "bookmarked": true | false }`

### `DELETE /lectures/:lecture_id/bookmarks`
- 認証: 必須
- 目的: 現在ユーザーの対象講義ブックマークを削除する。

## ありがとう

### `POST /reviews/:review_id/thanks`
- 認証: 必須
- 目的: 現在ユーザーが対象レビューにありがとうを送る。
- Response: `thanks_count` を含む。

### `GET /reviews/:review_id/thanks`
- 認証: 必須
- 目的: 現在ユーザーが対象レビューにありがとう済みか返す。
- Response: `thanked`, `thanks_count`

### `DELETE /reviews/:review_id/thanks`
- 認証: 必須
- 目的: 現在ユーザーのありがとうを取り消す。
- Response: `thanks_count` を含む。

## 管理設定

### `GET /admin/review-access`
- 認証: 管理者必須
- 目的: レビュー閲覧制限設定を返す。
- Response:
  - `lecture_review_restriction_enabled`
  - `updated_at`
  - `last_updated_by`

### `PATCH /admin/review-access`
- 認証: 管理者必須
- 目的: レビュー閲覧制限設定を更新する。
- Body:
  - `review_access.lecture_review_restriction_enabled`: `true` または `false`

## マイページ

### `GET /mypage`
- 認証: 必須
- 目的: 現在ユーザーのマイページ概要を返す。
- Response:
  - `user`
  - `statistics`
  - `bookmarked_lectures`
  - `user_reviews`
  - `ranking_position`

### `GET /mypage/reviews`
- 認証: 必須
- 目的: 現在ユーザーのレビュー一覧をページングして返す。
- Query:
  - `page`: 未指定時 1
  - `per_page`: 未指定時 10、最大 50
- Response:
  - `reviews`
  - `pagination`
  - `statistics`

### `GET /mypage/bookmarks`
- 認証: 必須
- 目的: 現在ユーザーのブックマーク講義一覧をページングして返す。
- Query:
  - `page`: 未指定時 1
  - `per_page`: 未指定時 10、最大 50
- Response:
  - `bookmarks`
  - `pagination`
  - `statistics`
