# frozen_string_literal: true

# ログイン利用者は同じ授業にレビューを1件だけ投稿できる、という制約を DB でも保証する。
# 匿名レビュー（user_id が NULL）は MySQL の一意インデックスでは重複扱いにならないため、
# これまでどおり同じ授業に何件でも保存できる。
#
# 既存データに重複があるときは、どれを残すかを運営者が判断する必要があるため、
# 自動で削除・統合せずに中断する。確認方法は docs/review-uniqueness-migration.md を参照。
class AddUniqueIndexToReviewsOnUserIdAndLectureId < ActiveRecord::Migration[8.1]
  INDEX_NAME = 'index_reviews_on_user_id_and_lecture_id'
  LISTED_GROUPS = 20

  DUPLICATES_SQL = <<~SQL.squish
    SELECT user_id, lecture_id, COUNT(*) AS review_count, GROUP_CONCAT(id ORDER BY id) AS review_ids
    FROM reviews
    WHERE user_id IS NOT NULL
    GROUP BY user_id, lecture_id
    HAVING COUNT(*) > 1
    ORDER BY user_id, lecture_id
  SQL

  def up
    return if index_exists?(:reviews, %i[user_id lecture_id], name: INDEX_NAME, unique: true)

    abort_if_duplicates

    begin
      add_index :reviews, %i[user_id lecture_id], unique: true, name: INDEX_NAME
    rescue ActiveRecord::RecordNotUnique
      # 確認の直後に重複が作られた場合も、同じ案内で中断する。
      abort_if_duplicates
      raise
    end
  end

  def down
    remove_index :reviews, name: INDEX_NAME, if_exists: true
  end

  private

  def abort_if_duplicates
    rows = select_rows(DUPLICATES_SQL)
    return if rows.empty?

    listed = rows.first(LISTED_GROUPS).map do |user_id, lecture_id, count, ids|
      "  user_id=#{user_id} lecture_id=#{lecture_id} 件数=#{count} review_ids=#{ids}"
    end
    listed << "  ...ほか #{rows.size - LISTED_GROUPS} 組" if rows.size > LISTED_GROUPS

    raise ActiveRecord::MigrationError, <<~MESSAGE
      reviews に同じ利用者・同じ授業のレビューが #{rows.size} 組あるため、一意インデックスを追加できません。
      データは変更していません。どのレビューを残すかを確認・整理してから、もう一度 migration を実行してください。
      重複の詳細: bin/rails reviews:duplicates
      手順: docs/review-uniqueness-migration.md
      #{listed.join("\n")}
    MESSAGE
  end
end
