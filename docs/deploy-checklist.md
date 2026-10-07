# Backend Deploy Checklist

## 対象

- `gatareview-back` の Heroku デプロイ
- review access、認証、CORS、reCAPTCHA、レスポンス契約の変更
- DB 接続先の切替

## 事前確認

1. ローカルで `docker compose run --rm gatareview-back bin/verify` を実行する
2. migration を追加した場合は `db/schema.rb` が期待通りであることを確認する
3. frontend 側の API 契約影響がある場合は frontend の `npm run verify` も通す

## Heroku 環境変数

変更がある場合は Heroku に反映し、再起動ではなく再デプロイ前提で扱う。

| 変数名 | 必須 | 確認内容 |
| --- | --- | --- |
| `JWT_SECRET_KEY` | Yes | 32バイト以上のランダムな専用鍵。未設定・空・短い鍵では起動を拒否する。Rails秘密鍵へのフォールバックはしない |
| `DATABASE_URL` | Yes | 本番DBの唯一の接続先。旧 `JAWSDB_URL` への自動フォールバックはない |
| `MYSQL_SSL_CA` | Provider-dependent | Aivenでは必須。Ruby buildpackで同梱する `config/certs/aiven-ca.pem` の実行時パス `/app/config/certs/aiven-ca.pem` を指定する。他の提供元でも独自CAを使う場合はその証明書のパスを指定する。未指定時はライブラリ既定のCAを使う |
| `GOOGLE_CLIENT_ID` | Feature-based | Google ログインの token 検証値 |
| `GOOGLE_CLIENT_SECRET` | Feature-based | Google OAuth 設定保持 |
| `RECAPTCHA_SECRET_KEY` | Feature-based | 本番レビュー投稿で必要 |
| `RECAPTCHA_ALLOWED_HOSTNAMES` | Yes | `www.gatareview.com,gatareview.com` のような許可ホスト名一覧 |
| `AUTH_RATE_LIMIT_PER_MINUTE` | Optional | Google認証APIのIP単位上限。既定値 `10` |
| `API_RATE_LIMIT_PER_FIVE_MINUTES` | Optional | API全体のIP単位上限。既定値 `300` |
| `FRONTEND_URL` | Recommended | `https://www.gatareview.com` |
| `ADMIN_EMAILS` | Feature-based | `/admin/review-access` に入るメールアドレス |

DB 移行を伴う切替は [aiven-migration-runbook.md](/Users/kawaiyuya/Desktop/gatareview/gatareview-back/docs/aiven-migration-runbook.md) の手順に従う。

### AivenのCA証明書

`config/certs/aiven-ca.pem` はAiven Consoleの接続情報から取得した公開CA証明書で、秘密鍵は含まない。証明書を含むコミットを先にデプロイしてから `MYSQL_SSL_CA` を設定する。ファイルがない旧リリースへのロールバック時には、この設定も旧リリースに合わせる必要がある。

CAのローテーション通知を受けたら、Aivenが配布する現在・次期CAを含むバンドル全体でファイルを更新し、期限と接続を確認して再デプロイする。証明書検証を無効化して接続を復旧しない。[Aivenの証明書要件](https://aiven.io/docs/platform/concepts/tls-ssl-certificates)

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

## 2026年10月のセキュリティ更新

- Ruby 3.4.11 / Rails 8.1.4 / Puma 7.2.1を使用する。
- 既存の十分に強い `JWT_SECRET_KEY` は維持できる。鍵を変更すると既存ユーザーは再ログインが必要になる。
- `token_version` を含む未適用のmigrationを、フロントの更新前に実行する。
- API失効に失敗した場合、フロントはログアウトを完了せず再試行を案内する。
- 本番MySQLは暗号化と証明書・ホスト名の検証を必須にする。DB提供元のCAを配置し、`Ssl_cipher` が空でないことと、誤ったCA・ホスト名の接続が拒否されることを反映前に確認する。

## 転送ヘッダーとリクエスト制限

- Herokuでは `DYNO` がある場合だけ、ルーターが `X-Forwarded-For` の右端に追加したIPを制限のキーに使う。利用者が送れる `Forwarded` や `Client-IP` はキーに使わない。
- Heroku以外では接続元の `REMOTE_ADDR` を使う。別のプロキシへ移す際は、そのプロキシが保証するヘッダーと信頼境界を確認してから変更する。
- 現在の本番設定はファイルのキャッシュを使い、同一dyno内のPumaワーカー間でカウンターを共有する。dynoを複数に増やす前に、専用のRedis等へ変更して全dynoで上限を共有する必要がある。再起動時には現在のカウンターが消える。
- Google認証の制限には `.json` と末尾 `/` の形式も含む。上限値は従来通り、Google認証がIPごとに毎分10件、API全体が5分300件。

## シラバス取得とイメージへの同梱

- シラバスの取得は管理用のコマンドに限定している。HTTPSの設定済み配信元と同じホスト・ポートへのリダイレクトだけを許可し、別ホスト、HTTP、認証情報を含むURLは接続前に拒否する。
- Dockerイメージには環境変数ファイル、Railsの復号鍵、DBダンプ、ブラウザ操作の記録や確認画像を含めない。環境変数と鍵は実行環境で管理する。
- CIはMySQL 8.4.12を使う。ローカルの旧DBは別ボリュームへ移す [移行手順](/Users/kawaiyuya/Desktop/gatareview/gatareview-back/docs/mysql84-local-migration.md) に従い、本番DBも提供元のバージョンとサポート期限を確認する。
