# 年次授業データ追加計画書

## 目的

新年度のシラバス公開後、ガタレビュに登録する授業データを年 1 回まとめて追加する。

現行の `Lecture` モデルは `title + lecturer + faculty` の組み合わせで重複登録を防いでいるため、同一学部をまとめて取り込んでも既存授業との重複は弾かれる前提で運用する。

## 現行運用の前提

- 授業データの取得元は新潟大学公式サイトのシラバス検索
  - 入口: `https://www.niigata-u.ac.jp/academics/syllabus/`
  - 遷移先: `https://syllabus.niigata-u.ac.jp/`
- `campussquare.do?_flowExecutionKey=...` の URL はセッション依存のため、手順書やブックマークには残さない
- 取込用 CSV は backend 直下に配置する
- 講義データ投入は `db:seed` ではなく `bin/rails lectures:import_csv CSV_PATH=...` を使う
- CSV のフォーマットはヘッダーなし 3 列
  - `授業名,担当教員名,学部ラベル`

例:

```csv
地理学実習Ｃ,太田 凌嘉,H:人文学部
法学概論,山田 太郎,L:法学部
```

## 対象範囲

シラバス検索の `開講所属` に表示される項目のうち、現在ガタレビュに登録対象として扱うのは以下。

| シラバス上の開講所属 | CSV に入れる faculty 値 |
| --- | --- |
| 人文学部 | `H:人文学部` |
| 教育学部 | `K:教育学部` |
| 法学部 | `L:法学部` |
| 経済科学部 | `E:経済科学部` |
| 理学部 | `S:理学部` |
| 医学部 | `M:医学部` |
| 歯学部 | `D:歯学部` |
| 工学部 | `T:工学部` |
| 農学部 | `A:農学部` |
| 創生学部 | `X:創生学部` |
| 全学共通 | `G:教養科目` |

補足:

- 上記は現行の `lectureData_2025.csv` に存在する登録対象に合わせる
- シラバス上に `経済学部` が表示されても登録対象には含めない。経済系は `経済科学部` のみを登録する
- 研究科、センター、経済学部などを追加対象にする場合は、CSV 作成ルールとフロント表示要件を別途確認する

## 年次作業の流れ

1. 新潟大学公式サイトのシラバス検索ページを開く
   - `https://www.niigata-u.ac.jp/academics/syllabus/`
   - ページ内の「新潟大学シラバス検索（Syllabus Search）」から遷移する
2. 検索画面で対象年度を設定する
   - 例: 2026 年度を追加するなら `年度 = 2026`
3. 対象学部ごとに `開講所属` を選択して検索する
4. 検索結果から `授業名` と `担当教員名` を取得し、対応する `faculty` 値を付与して一覧化する
5. すべての対象学部の結果を 1 つの CSV にまとめる
6. `gatareview-back/lectureData_<年度>.csv` を作成する
7. deploy 前に件数確認コマンドを実行して現在件数を控える
8. Heroku deploy 後に `bin/rails lectures:import_csv CSV_PATH=lectureData_<年度>.csv` を手動実行して取り込む
9. 再度件数確認コマンドを実行する
10. 管理画面または API / 画面から登録結果を spot check する

## 詳細手順

### 1. シラバス検索画面に入る

- 公式の入口ページから入る
- `campussquare.do?_flowExecutionKey=...` 付き URL の再利用はしない
- ブラウザのセッションが切れた場合は入口から入り直す

### 2. 学部ごとに検索する

各対象について、以下を繰り返す。

- `年度` を対象年度にする
- `開講所属` を 1 つ選ぶ
- `経済学部` は選ばない。経済系で取得するのは `経済科学部` のみ
- それ以外の条件は原則空欄
- `検索開始` を押す

### 3. 500 件超過時の対応

以下のメッセージが出た場合は、そのままでは全件表示できない。

`検索結果が最大表示件数（500）を超過しています。検索条件を追加してください。`

この場合は `開講` を追加条件にして分割取得する。

分割の基本方針:

- まず `開講所属` のみで検索する
- 500 件超過なら `開講` を 1 つずつ選んで再検索する
- 各結果を個別に回収し、後で結合する

`開講` の選択肢:

- 第1学期
- 第2学期
- 通年
- 集中
- 年度跨り
- 時間外
- 第1ターム
- 第2ターム
- 第3ターム
- 第4ターム
- 第1,2ターム
- 第3,4ターム
- 第2,3ターム
- 第1〜3ターム
- 第2〜4ターム

補足:

- 現行運用では `開講` の分割で対応する
- それでも 500 件を超える組み合わせが出た場合は、追加で `学年` などの条件で分割する

### 4. CSV に整形する

1 行につき以下の 3 項目だけを残す。

- `title`
- `lecturer`
- `faculty`

作成ルール:

- ヘッダー行は付けない
- 空行を入れない
- 文字コードは UTF-8
- `faculty` はシラバス表示名ではなく、ガタレビュ側の値を使う
- 同じ授業が複数回出ても seed 時に無視されるが、CSV 上でも可能な限り重複を減らす

### 5. ファイルを配置する

対象年度の CSV を backend 直下に置く。

例:

- `gatareview-back/lectureData_2026.csv`

注意:

- import 時は対象ファイル名を `CSV_PATH` で明示指定する
- 年度を更新しても rake task 側のコード変更は不要
### 6. deploy 前後で件数確認する

workspace ルートで以下を実行する。

```bash
docker-compose run --rm gatareview-back bin/rails lectures:count
docker-compose run --rm gatareview-back bin/rails lectures:count FACULTY='E:経済科学部'
```

ローカルで直接 Rails を実行する場合:

```bash
cd gatareview-back
bin/rails lectures:count
bin/rails lectures:count FACULTY='E:経済科学部'
```

Heroku では以下を実行する。

```bash
heroku run bin/rails lectures:count -a <APP_NAME>
heroku run bin/rails lectures:count FACULTY='E:経済科学部' -a <APP_NAME>
```

### 7. 本番へ手動 import する

Heroku deploy 完了後、対象 CSV を明示指定して import する。

```bash
heroku run bin/rails lectures:import_csv CSV_PATH=lectureData_2026.csv -a <APP_NAME>
```

## 確認項目

import 実行前:

- 対象年度が正しい
- 対象学部がすべて入っている
- CSV がヘッダーなし 3 列になっている
- `faculty` がガタレビュ側の値になっている
- 文字化けや空行がない

import 実行後:

- エラーなく完了している
- 想定件数の授業が追加されている
- 代表的な学部で授業検索ができる
- 既存授業の重複レコードが増えていない

## 既知の注意点

### 1. 重複判定の基準

重複判定は `title + lecturer + faculty` 単位。

以下は別授業として扱われる。

- 同じ授業名でも担当教員が違う
- 同じ授業名・担当教員でも faculty が違う

### 2. seed の挙動

`db:seed` は開発用テスト講義だけを対象にし、本番講義データ投入には使わない。

production では `db:seed` を実行しても講義 CSV は取り込まれない。

### 3. ファイル命名

backend 直下には `lectureData_<年度>.csv` を置く。

import task は `CSV_PATH` を明示指定するため、対象年次ファイルをそのまま使える。

## 改善候補

- シラバス検索結果から CSV を整形する補助スクリプトを作る
- lecture import の dry-run モードを用意する
- faculty ごとの差分レポートを出せるようにする
