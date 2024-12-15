# frozen_string_literal: true

FactoryBot.define do
  factory :lecture do
    title { '数学' }
    lecturer { '田中' }
    faculty { '理学部' }
  end
end
