# frozen_string_literal: true


# テスト用講義の手動作成
puts "テスト用講義を作成しています..."

test_lectures = [
  { title: 'プログラミング基礎', lecturer: '田中 太郎', faculty: 'T: 工学部' },
  { title: 'データベース設計', lecturer: '佐藤 花子', faculty: 'T: 工学部' },
  { title: 'Web開発入門', lecturer: '山田 次郎', faculty: 'T: 工学部' },
  { title: '情報セキュリティ', lecturer: '鈴木 三郎', faculty: 'T: 工学部' },
  { title: 'システム設計論', lecturer: '高橋 四郎', faculty: 'T: 工学部' },
  { title: 'アルゴリズム入門', lecturer: '伊藤 五郎', faculty: 'T: 工学部' },
  { title: 'コンピュータネットワーク', lecturer: '渡辺 六郎', faculty: 'T: 工学部' },
  { title: 'ソフトウェア工学', lecturer: '中村 七子', faculty: 'T: 工学部' },
  { title: '人工知能概論', lecturer: '小林 八郎', faculty: 'T: 工学部' },
  { title: 'マルチメディア処理', lecturer: '加藤 九子', faculty: 'T: 工学部' }
]

test_lectures.each do |lecture_data|
  lecture = Lecture.find_or_create_by(
    title: lecture_data[:title],
    lecturer: lecture_data[:lecturer],
    faculty: lecture_data[:faculty]
  )
  
  if lecture.persisted?
    puts "✅ 講義作成: #{lecture.title} (#{lecture.lecturer})"
  else
    puts "❌ 講義作成失敗: #{lecture_data[:title]} - エラー: #{lecture.errors.full_messages.join(', ')}"
  end
end

puts "テスト用講義の作成完了\n"

require 'csv'
require 'activerecord-import'

csv_file_path = Rails.root.join('lectureData_2025.csv')

puts "Seeding lectures from #{File.basename(csv_file_path)}..."
puts "重複する講義は無視され、既存データは削除されません。"

unless File.exist?(csv_file_path)
  puts "エラー: CSVファイルが見つかりません: #{csv_file_path}"
  exit 1
end

lectures_to_import = []
skipped_rows_count = 0
total_rows_processed = 0

CSV.foreach(csv_file_path, headers: false, encoding: 'UTF-8') do |row|
  total_rows_processed += 1
  title = row[0]&.strip
  lecturer = row[1]&.strip
  faculty = row[2]&.strip

  # 必須項目が一つでも空ならスキップし、情報を表示
  if title.blank? || lecturer.blank? || faculty.blank?
    puts "[行 #{total_rows_processed}] スキップ: 必須項目 (title, lecturer, faculty) のいずれかが空です。 データ: [#{row.join(', ')}]"
    skipped_rows_count += 1
    next
  end

  # 有効なデータを Lecture オブジェクトとして配列に追加
  lectures_to_import << Lecture.new(title: title, lecturer: lecturer, faculty: faculty)
end
puts "--- CSVデータ読み込み完了 ---"
puts "#{total_rows_processed} 行を処理しました。"
puts "#{skipped_rows_count} 行が必須項目不足のためスキップされました。"
puts "------------------------------------"

if lectures_to_import.any?
  puts "#{lectures_to_import.size} 件の有効なデータをインポートします..."
  Lecture.import lectures_to_import, validate: false, ignore: true
  puts "インポート処理を実行しました。"
  puts "(データベースに存在しない新しいレコードのみが追加されました)"
else
  puts "CSVファイルにインポート対象の有効なデータが見つかりませんでした。"
end

puts 'Seed処理が完了しました。'
