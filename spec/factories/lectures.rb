# frozen_string_literal: true

FactoryBot.define do
  factory :lecture do
    sequence(:title) { |n| "数学#{n}" }
    sequence(:lecturer) { |n| "田中#{n}" }
    faculty { '理学部' }
  end
end
