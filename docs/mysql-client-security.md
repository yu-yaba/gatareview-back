# MySQL接続部品のセキュリティ更新

## 対象と根拠

本番のHerokuはCedar・heroku-26・Ecoを使う。Ubuntu 26.04の公式配布元で利用できるlibmysqlclient24は8.4.11-0ubuntu0.26.04.1で、10月の修正取り込みを確認できなかった。Oracle公式が配布する8.4.13-1ubuntu24.04のクライアントをアプリに同梱し、DB本体のバージョンとは分けて更新する。

`mysql2` gemの版は0.5.7を維持する。実際にロードするlibmysqlclientと、mysql・mysqldump等のクライアントを8.4.13にする。DBサーバーパッケージをインストールせず、AivenのDB更新・移行・権限変更は行わない。

## Herokuでの適用

Heroku公式APTビルドパックをRubyより前に実行する。検証した版は以下のコミットに固定する。

```text
https://github.com/heroku/heroku-buildpack-apt.git#b6a5d7b9fcc67cc073c87161a9f3bd24fea5d10e
heroku/ruby
```

`Aptfile` のOracle公式HTTPS URLから接続部品を `.apt` に展開する。OS全体のライブラリやDBを上書きせず、公式ビルドパックが設定するLD_LIBRARY_PATHとPATHによりアプリから同梱版を使う。

取得時に公式PackagesのSHA-256を照合した。配布物の一覧・版・SHA-256は `config/mysql-client-packages.json`、実行ファイル・共有ライブラリ・そのシンボリックリンクの検証値は `config/mysql-client-files.sha256` に保存する。起動時の `.profile.d/001_mysql_client.sh` はRubyがライブラリをロードする前に18ファイルのハッシュを照合し、不一致・欠落なら起動を拒否する。

本番のHerokuでは、Rails起動時にも実際のクライアントIDが8.4.13以上の8.4系か確認する。古いライブラリや別の系列なら起動を拒否する。ログには版番号だけを記録し、接続先・ユーザー・資格情報は出さない。初期化時のローカル検査なのでDBへの追加クエリは発生しない。

この配布物はLinux amd64用。Herokuの本番で検証する。macOSやarm64のローカル環境は既存の接続部品を使い、amd64用の `.apt` を持ち込まない。ローカルのDocker構成や本番と異なるクライアントの安全性を、このHeroku向けの検証だけで保証しない。

## 検証

- 全RSpecとRuboCopは、仮の鍵・隔離DBを使って `bin/verify` で確認する。
- 改変されたライブラリと8.4.11/8.4.12を拒否するテストを実行する。
- 本番反映前に、既存Eco利用枠の短時間プロセスから新しいライブラリを一時ロードし、読み取りSQLで接続を確認する。WebプロセスとDBは変更しない。
- 本番反映後に、MySQL client runtimeのログ、mysql2がロードした版、主要APIの応答、TLSの証明書・ホスト名検証を確認する。ログや公開コメントへ資格情報を含めない。

更新前のネイティブ拡張のヘッダー表示が8.4.11でも、実行時にロードしたライブラリが8.4.13であることを確認する。8.4系のSONAME 24を維持した差し替えであり、gemの表示だけで更新済みと判断しない。

## 費用と戻し方

追加のアドオンや有料プランは使わず、既存のEco・Aiven無料プランを維持する。検証プロセスはEcoを明示し、他の有料サイズへ切り替えない。Ecoの時間枠を消費するが、時間枠の追加購入は行わない。

新しいリリースで異常が出た場合は、確認済みの直前リリースへ戻す。ビルドパックの設定も変更前のheroku/rubyだけへ戻す。DBの書き換えや移行を伴わないため、DBを復元して戻す作業は不要。次回更新では公式PackagesとファイルのSHA-256を再取得し、接続・TLS・全テストを再実行する。

根拠: [Oracleのパッケージ情報](https://repo.mysql.com/apt/ubuntu/dists/noble/mysql-8.4-lts/binary-amd64/Packages)、[MySQLの10月の修正](https://dev.mysql.com/doc/relnotes/mysql/8.4/en/news-8-4-13.html)、[Heroku公式APTビルドパック](https://github.com/heroku/heroku-buildpack-apt)、[Eco利用枠](https://devcenter.heroku.com/articles/eco-dyno-hours)。
