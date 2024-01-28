# # フェイカーを使用してランダムデータを生成します
# require 'faker'

# Faker::Config.locale = :ja

# # 学部のオプション
# faculties = ['G: 教養科目', 'H: 人文学部', 'K: 教育学部', 'L: 法学部', 'E: 経済科学部',
#              'S: 理学部', 'M: 医学部', 'D:】＿？＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿＿_________________________ 歯学部', 'T: 工学部', 'A: 農学部', 'X: 創生学部']

# # 講義名のオプション
# lecture_titles = [
#   '微積分学Ⅰ', '物理学概論', '情報科学入門', '統計学基礎', '線形代数学', '現代日本語', '経済数学', '日本文学Ⅰ', '科学基礎A',
#   '生物学入門', '現代社会理論', '応用倫理学', '経済政策', '宇宙論', '生態学', 'プログラミング基礎', 'データサイエンス',
#   '化学原理', '量子力学', '日本史概観', '心理学入門', '生命科学', '電気電子工学', '有機化学', 'ビジネス英語',
#   'データベース基礎', '地球環境学', '神経科学', 'オペレーションズ・リサーチ', 'マクロ経済学', 'ミクロ経済学',
#   '言語学入門', 'コンピュータアーキテクチャ', 'アルゴリズム理論', '微分方程式', '生化学', '統計力学',
#   '日本経済論', '数理統計学', '民法概説', '物質科学'
# ]

# # レビューのコメントのオプション
# review_comments = ['授業はわかりやすかった。', '難しい内容だったが、教授の説明が上手い。', '試験が難しかった。', '自習が必要な授業。', '参考書があると理解しやすい。']

# # レビューの各属性のオプション
# period_years = %w[2023 2022 2021 2020]
# period_terms = ['1ターム', '2ターム', '1, 2ターム', '3ターム', '4ターム', '3, 4ターム']
# textbooks = %w[必要 不要]
# attendances = %w[毎回確認 たまに確認 なし]
# grading_types = ['テストのみ', 'レポートのみ', 'テスト,レポート', 'その他']
# content_difficulties = %w[とても楽 楽 普通 難しい とても難しい]
# content_qualities = %w[とても良い 良い 普通 悪い とても悪い]

# 200.times do |_i|
#   lecture_title = lecture_titles.sample

#   lecture = Lecture.create!(
#     title: lecture_title,
#     lecturer: Faker::Name.name,
#     faculty: faculties.sample
#   )

#   # 各講義に対して2つのレビューを生成します
#   2.times do
#     Review.create!(
#       rating: rand(1..5),
#       period_year: period_years.sample,
#       period_term: period_terms.sample,
#       textbook: textbooks.sample,
#       attendance: attendances.sample,
#       grading_type: grading_types.sample,
#       content_difficulty: content_difficulties.sample,
#       content_quality: content_qualities.sample,
#       content: review_comments.sample,
#       lecture_id: lecture.id
#     )
#   end
# end

require 'csv'

CSV.foreach(Rails.root.join('lectureData.csv'), headers: false, encoding: 'UTF-8') do |row|
  title, lecturer, faculty = row.map(&:strip)

  if title && lecturer && faculty
    lecture = Lecture.new(title: title, lecturer: lecturer, faculty: faculty)
    if lecture.save
      puts "Added lecture: #{lecture.title}"
    else
      puts "エラーが発生しました: #{lecture.errors.full_messages.join(", ")}"
    end
  else
    puts "無効な行: #{row}"
  end
end
