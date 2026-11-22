# frozen_string_literal: true

# reviews.lecture_id を文字列から lectures.id と同じ bigint に揃え、外部キーを付ける。
#
# MySQL は文字列と数値を暗黙に変換して結合するが、PostgreSQL は型が違うと
# `joins(:reviews)` が失敗する。PostgreSQL へ移す前に型を揃えておく。
# 数字以外の値や存在しない授業を指す値があるときは、データを変えずに中断する。
class ChangeReviewsLectureIdToBigint < ActiveRecord::Migration[8.1]
  INVALID_IDS_SQL = <<~SQL.squish
    SELECT r.id, r.lecture_id
    FROM reviews r
    LEFT JOIN lectures l ON l.id = r.lecture_id
    WHERE r.lecture_id IS NULL
       OR r.lecture_id NOT REGEXP '^[1-9][0-9]*$'
       OR CAST(CAST(r.lecture_id AS UNSIGNED) AS CHAR) <> r.lecture_id
       OR l.id IS NULL
    ORDER BY r.id
    LIMIT 20
  SQL

  def up
    # 長く開いたトランザクションがあると ALTER がロック待ちのまま止まり、後続の reviews への
    # クエリも詰まる。待つのは10秒までにして、その場合は失敗させてやり直す。
    execute 'SET SESSION lock_wait_timeout = 10'
    abort_if_invalid_lecture_ids

    change_column :reviews, :lecture_id, :bigint, null: false
    # 本番には未使用列 lecture_id_bigint から lectures への外部キーが残っているため、
    # 列を指定して確かめる（列を指定しないとそれを見つけて追加を飛ばしてしまう）。
    return if foreign_key_exists?(:reviews, :lectures, column: :lecture_id)

    add_foreign_key :reviews, :lectures, column: :lecture_id
  end

  def down
    remove_foreign_key :reviews, :lectures, column: :lecture_id, if_exists: true
    change_column :reviews, :lecture_id, :string, null: true
  end

  private

  def abort_if_invalid_lecture_ids
    rows = select_rows(INVALID_IDS_SQL)
    return if rows.empty?

    listed = rows.map { |id, lecture_id| "  review_id=#{id} lecture_id=#{lecture_id.inspect}" }
    raise ActiveRecord::MigrationError, <<~MESSAGE
      reviews.lecture_id に、数字でない値か存在しない授業を指す値があるため、bigint に変換できません。
      データは変更していません。該当するレビューを確認・修正してから、もう一度 migration を実行してください。
      #{listed.join("\n")}
    MESSAGE
  end
end
