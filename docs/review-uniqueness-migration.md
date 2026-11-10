# レビュー一意インデックスの本番適用手順

`20261109000000_add_unique_index_to_reviews_on_user_id_and_lecture_id.rb` は、ログインユーザーが同じ授業にレビューを1件しか持てないことを DB の一意インデックス `index_reviews_on_user_id_and_lecture_id`（`reviews(user_id, lecture_id)`）で保証する。

これまでは model の検証だけだったため、同時に届いた投稿や通信のやり直しで重複が作られていた可能性がある。重複が残っているとインデックスを追加できないので、migration は**データを変更せずに中断し、重複の一覧を表示する**。どのレビューを残すかは運営者が判断する（自動で削除・統合はしない）。

匿名レビュー（`user_id` が NULL）は MySQL の一意インデックスでは重複扱いにならないため対象外。

## 順番

Heroku は `main` へのマージで自動デプロイされるが、migration は自動では実行されない。コードは migration の前後どちらでも動く（インデックスがない間も、投稿は利用者の行をロックしてから確認・保存するので、同じ利用者の同時投稿は1件にまとまる）。

1. マージ前に、本番 DB で重複があるかを読み取りだけの SQL で確認する（下記）
2. 重複があれば、残すレビューを決めて整理する（下記）。整理が済むまで 4 は実行しない
3. マージして自動デプロイを待つ
4. 本番で migration を実行する

```bash
heroku run bin/rails reviews:duplicates -a gatareview-back
heroku run bin/rails db:migrate:status -a gatareview-back
heroku run bin/rails db:migrate -a gatareview-back
```

- `reviews:duplicates` は読み取りだけ。重複がなければ「重複はありません」と表示して終了コード0、あれば一覧を表示して終了コード1で終わる。本文は表示せず、文字数と本文ハッシュ（同じなら同じ内容の再送）だけを出す
- `db:migrate:status` で `down` がこの migration だけであることを確かめてから `db:migrate` を実行する
- 本番 DB を更新する前に、いつもどおりバックアップを保存する

## 1. マージ前の確認（読み取りのみ）

まだ `reviews:duplicates` がデプロイされていないので、Aiven Console のクエリ画面か、本番 DB に読み取りで接続した MySQL クライアントで次を実行する。

```sql
SELECT user_id, lecture_id, COUNT(*) AS review_count, GROUP_CONCAT(id ORDER BY id) AS review_ids
FROM reviews
WHERE user_id IS NOT NULL
GROUP BY user_id, lecture_id
HAVING COUNT(*) > 1
ORDER BY user_id, lecture_id;
```

0行なら重複はない。3 へ進んでよい。

重複があった組は、各レビューの違いを確かめる（本文は画面に出さず、長さとハッシュで比べる）。

```sql
SELECT id, user_id, lecture_id, created_at, updated_at, rating, CHAR_LENGTH(content) AS content_length,
       LEFT(SHA2(content, 256), 12) AS content_hash, thanks_count
FROM reviews
WHERE (user_id, lecture_id) IN ((<user_id>, '<lecture_id>'))
ORDER BY user_id, lecture_id, id;
```

## 2. 重複の整理（運営者の判断で実行）

自動では行わない。組ごとに次の方針で決める。

- 本文ハッシュも評価も同じ（同じ内容の再送）: 古い方（id の小さい方）を残し、新しい方を削除する。ありがとうが付いていれば、削除前に残す方へ付け替えるか、付け替えずに削除してよいかを決める
- 内容が違う: 本人が書き直したものとみなし、どちらを残すかを決める。迷う場合は新しい方（`updated_at` が新しい方）を残す

削除はアプリと同じ後処理（`users.reviews_count` の更新、`thanks` の削除）が走るように、Rails コンソールから1件ずつ行う。

```bash
heroku run bin/rails console -a gatareview-back
```

```ruby
Review.find(<削除するid>).destroy!
```

整理後に 1 の SQL（デプロイ後なら `bin/rails reviews:duplicates`）で0行になったことを確かめてから migration を実行する。

## migration が中断したとき

`reviews に同じ利用者・同じ授業のレビューが N 組あるため、一意インデックスを追加できません。` と表示されて止まった場合、データとスキーマは変更されていない。表示された一覧か `bin/rails reviews:duplicates` で重複を確かめ、2 の手順で整理してから再実行する。

確認と追加の間に新しい重複が作られた場合も、同じ案内で中断する。

## 戻すとき

```bash
heroku run bin/rails db:migrate:down VERSION=20261109000000 -a gatareview-back
```

インデックスを外すだけで、データは変更しない。インデックスがなくてもアプリは動く。
