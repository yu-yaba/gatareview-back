# frozen_string_literal: true

if Rails.env.production?
  puts 'production では db:seed で講義データを投入しません。'
  puts '講義 CSV の投入は bin/rails lectures:import_csv CSV_PATH=... を使用してください。'
else
  puts 'テスト用講義を作成しています...'

  [
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
  ].each do |lecture_data|
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
end
