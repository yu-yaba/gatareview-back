## 概要

- 何を変えたか
- どの API / 画面に影響するか

## 変更対象

- [ ] API 契約
- [ ] 認証
- [ ] review access
- [ ] migration
- [ ] deploy 手順

## 環境変数 / デプロイ影響

- [ ] 新しい Heroku 環境変数あり
- [ ] migration が必要
- [ ] frontend の同時デプロイが必要
- [ ] 追加対応なし

必要な設定があれば記載:

## 確認

- [ ] `docker compose run --rm gatareview-back bin/verify`
- [ ] `docs/deploy-checklist.md` を確認

## 手動確認

- [ ] `/api/v1/lectures/:id`
- [ ] `/api/v1/lectures/:id/reviews`
- [ ] `/api/v1/reviews/latest`
- [ ] `/api/v1/auth/me`
- [ ] `/api/v1/admin/review-access`（該当時）

## 補足

- curl、スクリーンショット、migration 注意点があれば記載
