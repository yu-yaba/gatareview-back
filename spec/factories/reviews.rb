# frozen_string_literal: true

FactoryBot.define do
  factory :review do
    rating { 5 }
    content { 'この授業は内容が分かりやすく、課題も適度で学びが多かったです。おすすめです。' }
    period_year { 2023 }
    period_term { '春' }
    textbook { '必要' }
    attendance { '毎回確認' }
    grading_type { 'テストのみ' }
    content_difficulty { '普通' }
    content_quality { '良い' }
    association :lecture
  end
end
