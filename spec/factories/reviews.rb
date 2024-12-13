# frozen_string_literal: true

FactoryBot.define do
  factory :review do
    rating { 5 }
    content { "とても良い講義でした。" }
    period_year { 2023 }
    period_term { "春" }
    textbook { "良い教科書" }
    attendance { "必須" }
    grading_type { "テスト中心" }
    content_difficulty { "適度" }
    content_quality { "高い" }
    association :lecture
  end
end
