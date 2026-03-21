# Backend Deploy Checklist

## 対象

- `gatareview-back` の Heroku デプロイ
- review access、認証、CORS、reCAPTCHA、レスポンス契約の変更

## 事前確認

1. ローカルで `docker compose run --rm gatareview-back bin/verify` を実行する
2. migration を追加した場合は `db/schema.rb` が期待通りであることを確認する
3. frontend 側の API 契約影響がある場合は frontend の `npm run verify` も通す

## Heroku 環境変数

変更がある場合は Heroku に反映し、再起動ではなく再デプロイ前提で扱う。

| 変数名 | 必須 | 確認内容 |
| --- | --- | --- |
| `JWT_SECRET_KEY` | Recommended | 空でない。未設定時は `RAILS_SECRET_KEY_BASE` を使うが専用キー推奨 |
| `GOOGLE_CLIENT_ID` | Feature-based | Google ログインの token 検証値 |
| `GOOGLE_CLIENT_SECRET` | Feature-based | Google OAuth 設定保持 |
| `RECAPTCHA_SECRET_KEY` | Feature-based | 本番レビュー投稿で必要 |
| `FRONTEND_URL` | Recommended | `https://www.gatareview.com` |
| `ADMIN_EMAILS` | Feature-based | `/admin/review-access` に入るメールアドレス |

## migration

review access 関連では env 追加と別に migration が必要になる。

```bash
heroku run bin/rails db:migrate -a gatareview-back-b726b6ea4bcf
```

注意:

- `site_settings` は env ではなく DB テーブル
- lecture detail reviews が production で 500 のときは `site_settings` migration 未実行を先に疑う

## 本番 API 確認

少なくとも以下を確認する。

- `GET /api/v1/lectures/:id`
- `GET /api/v1/lectures/:id/reviews`
- `GET /api/v1/reviews/latest`
- `GET /api/v1/auth/me`
- `GET /api/v1/admin/review-access`（管理者トークンで）

## review access 変更時の確認

1. `site_settings` テーブルが存在する
2. 管理者が `/admin/review-access` に入れる
3. 制限 `OFF`
   - 未ログインで授業詳細レビューが全文表示される
4. 制限 `ON`
   - 未ログインでは 2 件目以降が制限される
   - `reviews_count >= 1` ユーザーは全文閲覧できる
5. `latest` や授業一覧などの影響範囲外 API が変わっていない

## ログ確認

- `Google token verification failed`
- `RECAPTCHA_SECRET_KEY is not set`
- `Failed to load review restriction setting`

これらが出ている場合は env / migration 漏れを優先して確認する。
