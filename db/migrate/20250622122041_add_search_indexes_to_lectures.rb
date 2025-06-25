class AddSearchIndexesToLectures < ActiveRecord::Migration[7.0]
  def change
    # 通常のB-treeインデックス
    add_index :lectures, :title
    add_index :lectures, :lecturer
    add_index :lectures, [:title, :lecturer], name: 'index_lectures_on_title_and_lecturer'
    
    # PostgreSQLのILIKE検索用のGINインデックス（部分文字列検索に最適）
    if connection.adapter_name.downcase.include?('postgresql')
      # trigramエクステンションを有効化
      execute "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
      
      # GINインデックスでILIKE検索を高速化
      execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS index_lectures_on_title_gin ON lectures USING gin(title gin_trgm_ops);"
      execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS index_lectures_on_lecturer_gin ON lectures USING gin(lecturer gin_trgm_ops);"
    end
    
    # レビューテーブルのインデックス
    add_index :reviews, :lecture_id unless index_exists?(:reviews, :lecture_id)
    
    # レビュー検索用の複合インデックス
    add_index :reviews, [:lecture_id, :period_year]
    add_index :reviews, [:lecture_id, :content_difficulty]
    add_index :reviews, [:lecture_id, :content_quality]
  end
  
  def down
    if connection.adapter_name.downcase.include?('postgresql')
      execute "DROP INDEX CONCURRENTLY IF EXISTS index_lectures_on_title_gin;"
      execute "DROP INDEX CONCURRENTLY IF EXISTS index_lectures_on_lecturer_gin;"
    end
    
    remove_index :reviews, [:lecture_id, :content_quality] if index_exists?(:reviews, [:lecture_id, :content_quality])
    remove_index :reviews, [:lecture_id, :content_difficulty] if index_exists?(:reviews, [:lecture_id, :content_difficulty])
    remove_index :reviews, [:lecture_id, :period_year] if index_exists?(:reviews, [:lecture_id, :period_year])
    remove_index :reviews, :lecture_id if index_exists?(:reviews, :lecture_id)
    remove_index :lectures, [:title, :lecturer] if index_exists?(:lectures, [:title, :lecturer])
    remove_index :lectures, :lecturer if index_exists?(:lectures, :lecturer)
    remove_index :lectures, :title if index_exists?(:lectures, :title)
  end
end
