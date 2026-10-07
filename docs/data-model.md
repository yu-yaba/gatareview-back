# バックエンド設計書: データモデル

## 概要
現行スキーマは `db/schema.rb` を正とする。主要テーブルは `users`, `lectures`, `reviews`, `bookmarks`, `thanks`, `site_settings` である。

## users
Google OAuth でログインしたユーザーを表す。

主なカラム:
- `email`: 必須、一意。
- `name`: 必須。
- `provider`: 必須。現行は `google`。
- `provider_id`: 必須。Google の `sub`。
- `avatar_url`: Google profile image。
- `reviews_count`: レビュー数の counter cache。

関連:
- `has_many :reviews`
- `has_many :thanks`
- `has_many :bookmarks`
- `has_many :updated_site_settings`

制約と index:
- `email` は unique。
- `provider`, `provider_id` の組み合わせは unique。

権限:
- `admin?` は `ADMIN_EMAILS` と `ADMIN_EMAIL` の環境変数で判定する。

## lectures
講義マスタを表す。

主なカラム:
- `title`: 講義名。必須。
- `lecturer`: 担当教員。必須。
- `faculty`: 学部。必須。

関連:
- `has_many :reviews`
- `has_many :bookmarks`

制約と index:
- `title`, `lecturer`, `faculty` の組み合わせは unique。
- `title`, `lecturer` に検索用 index がある。
- 登録前に `title`, `lecturer`, `faculty` の前後空白を除去する。

検索:
- `search_by_title_and_lecturer` は MySQL の `LIKE` で講義名・教員名を部分一致検索する。

JSON 整形:
- `as_json_reviews` は一覧用に `avg_rating` と `review_count` を付与する。
- `as_json_with_reviews` は詳細用に平均評価とレビュー数を付与する。

## reviews
講義に対するレビューを表す。

主なカラム:
- `rating`: 評価。必須。
- `content`: 本文。必須、最大 1000 文字。
- `lecture_id`: 講義 ID。現行 schema では string。
- `user_id`: 投稿者。匿名投稿の場合は null。
- `textbook`: 教科書。
- `attendance`: 出席。
- `grading_type`: 評価方法。
- `content_difficulty`: 内容の難易度。
- `content_quality`: 内容の質。
- `period_year`: 受講年度。
- `period_term`: 学期。
- `thanks_count`: ありがとう数。default 0。

関連:
- `belongs_to :lecture`
- `belongs_to :user, optional: true, counter_cache: true`
- `has_many :thanks`

制約と index:
- ログインユーザーは `user_id` と `lecture_id` の組み合わせで一意。
- `user_id` が null の匿名レビューは一意制約対象外。
- `lecture_id` とレビュー詳細項目の複合 index があり、詳細検索に使う。

注意:
- `lecture_id` は schema 上 string だが、`belongs_to :lecture` として扱われている。変更する場合は migration、model、検索、既存データ移行を同時に検討する。

## bookmarks
ユーザーが講義をブックマークした状態を表す。

主なカラム:
- `user_id`
- `lecture_id`

関連:
- `belongs_to :user`
- `belongs_to :lecture`

制約と index:
- `user_id`, `lecture_id` の組み合わせは unique。
- `user_id` と `lecture_id` に個別 index がある。

挙動:
- 同じユーザーが同じ講義を複数回ブックマークすることはできない。
- 講義詳細で単体状態を取得し、マイページで一覧表示する。

## thanks
ユーザーがレビューに送ったありがとうを表す。

主なカラム:
- `user_id`
- `review_id`

関連:
- `belongs_to :user`
- `belongs_to :review`

制約と index:
- `user_id`, `review_id` の組み合わせは unique。
- `user_id` と `review_id` に個別 index がある。

挙動:
- 作成・削除時にレビューの `thanks_count` を再取得して返す。
- 同じユーザーが同じレビューに複数回ありがとうを送ることはできない。

## site_settings
サイト全体の設定を保持する singleton テーブルである。

主なカラム:
- `lecture_review_restriction_enabled`: レビュー閲覧制限の有効/無効。default false。
- `last_updated_by_user_id`: 最終更新者。
- `singleton_guard`: singleton 制約用。default 1。

関連:
- `belongs_to :last_updated_by, class_name: 'User'`

制約と index:
- `singleton_guard` は unique。
- singleton として `SiteSetting.current` / `current!` から参照する。

挙動:
- 管理画面で更新する。
- レビュー一覧 API が閲覧制限判定に使う。

## ER 概要
```text
users 1 --- * reviews * --- 1 lectures
users 1 --- * bookmarks * --- 1 lectures
users 1 --- * thanks * --- 1 reviews
users 1 --- * site_settings(last_updated_by)
```

## データ整合性の注意
- レビュー削除時は関連する `thanks` を削除する。
- ユーザー削除時は `reviews`, `thanks`, `bookmarks` を削除し、更新済み site setting の更新者は null にする。
- 講義削除時は `bookmarks` は削除されるが、`reviews` は model 上 dependent 指定がないため、削除仕様を変更する場合は影響確認が必要。
- `reviews_count` と `thanks_count` は表示・権限制御に使われるため、直接 SQL 更新時は counter の整合性に注意する。
