# ローカル MySQL 8.4 への移行

CI は Oracle 公式レジストリの MySQL 8.4.12 を使います。DockerHub の同名タグは配布されていないため、`container-registry.oracle.com/mysql/community-server` を指定します。既存のローカル DB データを保持するため、通常の `docker-compose.yml` は 8.0 系の最終版 8.0.46 に留め、8.4 は別のボリュームを使う追加設定で起動します。8.0 はサポート終了のため、移行を終えた後は追加設定を使ってください。[MySQL 公式リリースノート](https://dev.mysql.com/doc/relnotes/mysql/8.0/en/)

追加設定の既定タグ `8.4.12-aarch64` は Apple Silicon 向けです。Intel Mac や Linux amd64 では、`MYSQL84_IMAGE_TAG=8.4.12` を設定して同じ手順を実行します。CI は amd64 タグを使います。8.4.12 は Docker イメージを対象にしたセキュリティ更新です。[8.4.12 の公式告知](https://dev.mysql.com/doc/relnotes/mysql/8.4/en/news-8-4-12.html)

## 既存データを移す手順

1. アプリへの書き込みを停止し、8.0 の DB から `mysqldump --single-transaction --set-gtid-purged=OFF --column-statistics=0` で利用中データベースのダンプを取得します。認証は `-p` の対話入力で行い、パスワードをコマンドへ直書きしません。ダンプは Git や Docker イメージに含めず、復元まで安全に保管します。
2. 8.0 の DB を停止します。既存ボリュームは残し、`down -v` は使いません。
3. workspace 直下で `docker compose -f docker-compose.yml -f docker-compose.mysql84.yml up -d db` を実行します。8.4 は新しい `gatareview-mysql84-data` ボリュームを使い、古いデータ領域を変更しません。
4. 同じ追加設定を付けた DB にダンプを復元します。DBユーザーと権限も確認してください。Oracle イメージの `root` 接続は追加設定でローカルDockerネットワークから許可していますが、DBポートはホストに公開しません。通常ユーザーを使う場合は、新DBにもそのユーザー・権限を作成します。テーブル件数と重要データを比較し、`bin/verify` と授業・レビューの表示を確認します。
5. 確認後は、アプリの起動にも両方の設定ファイルを指定します。旧ボリュームとダンプは復元確認が済むまで保持します。

## ロールバック

8.4 で追加・更新したデータがある場合は、切替前に整合を確認してください。8.4 の DB を停止し、通常の `docker-compose.yml` だけで 8.0.46 を起動すると旧ボリュームへ戻ります。8.4 のデータ領域を8.0へ直接渡す方法は使いません。

## 本番 DB

この手順はローカルの DB だけを対象にします。本番提供元の MySQL バージョンとサポート期限を確認し、提供元のバックアップ・アップグレード手順に従って別途移行してください。今回の調査では本番 DB の変更を行っていません。
