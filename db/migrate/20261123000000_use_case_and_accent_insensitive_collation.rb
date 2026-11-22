# frozen_string_literal: true

# MySQL（utf8mb4_0900_ai_ci）と同じく、大文字小文字・全角半角・ひらがなカタカナ・濁点の有無などを
# 区別せずに比べる照合順序を作り、授業名・教員名・学部とメールアドレスに使う。
#
# 検索（LIKE）と一意制約の両方がこの照合順序で比べるため、MySQL のときと同じ授業がヒットし、
# 同じものとみなされる組み合わせは重複として弾かれる。
# LIKE で非決定的な照合順序を使えるのは PostgreSQL 18 以降。
#
# この migration は PostgreSQL へ移したあとの DB だけで流す（MySQL では流さない）。
class UseCaseAndAccentInsensitiveCollation < ActiveRecord::Migration[8.1]
  COLLATION = 'ci_ai'
  COLUMNS = {
    lectures: %i[title lecturer faculty],
    users: %i[email]
  }.freeze

  def up
    execute <<~SQL.squish
      CREATE COLLATION IF NOT EXISTS #{COLLATION}
        (provider = icu, locale = 'und-u-ks-level1', deterministic = false)
    SQL
    each_column { |table, column, null| change_column table, column, :string, null: null, collation: COLLATION }
  end

  def down
    each_column { |table, column, null| change_column table, column, :string, null: null, collation: 'default' }
    execute "DROP COLLATION IF EXISTS #{COLLATION}"
  end

  private

  def each_column
    COLUMNS.each do |table, columns|
      columns.each do |column|
        null = connection.columns(table).find { |c| c.name == column.to_s }.null
        yield table, column, null
      end
    end
  end
end
