# エラー監視

Sentryの無料枠で、Railsの予期しない例外を収集する。HerokuのProductionに`SENTRY_DSN`を設定し、この変更をデプロイする。Development・Testは無効。DBスキーマとAPIの応答形式は変更しない。

エラーの種類、コードのファイル名・関数名・行番号、環境・リリースだけを送る。元のメッセージは固定文へ置き換え、ユーザー情報、Cookie、認証情報、入力本文、URLクエリ、SQL、ソースコード、ローカル変数、添付情報は送信データから除く。新しいSDKのフィールドも許可した情報以外は送らない。

トレース、画面録画、ログ全量収集、メトリクスは送信しない。Sentry側でもIP保存とソースコード取得を無効にする。追加従量課金・有料プラン・Seerは使わない。

Sentry Developerの月5,000エラーは同じ組織の全プロジェクトで共有する。新規・再発をメールで受け取り、使用量も確認する。無料体験中の上限を恒久の無料枠と混同しない。

UptimeRobot Freeは公開API`/api/v1/lectures?per_page=1`を5分間隔で読み取り、応答に`"lectures":`がなければ通知する。このAPIのページサイズは現在20件固定で、`per_page=1`はサイズを変えない。認証や書き込みを伴うURLは監視しない。

Heroku Ecoは月1,000時間を同じアカウントの全アプリで共有し、定期アクセスによりスリープしなくなる。2026-11-03の導入前確認では対象アプリは1つ、残り約942時間。アプリ・ワーカーを追加する際は合計利用時間を再確認する。監視サービスの追加料金はなく、既存のHeroku料金は継続する。

検証は`bin/verify`。機密情報除外は`spec/services/sentry_privacy_spec.rb`で、実際のSDK送信先をメモリへ置き換えて確認する。反映後は実環境のSDKからテスト例外を送り、Sentryの受信とメール通知を確認する。停止時は`SENTRY_DSN`を外し、UptimeRobotのAPI監視をpauseする。

公式資料: [Rails導入](https://docs.sentry.io/platforms/ruby/guides/rails/)、[Sentry無料枠](https://sentry.io/pricing/)、[Heroku Eco利用時間](https://devcenter.heroku.com/articles/eco-dyno-hours)
