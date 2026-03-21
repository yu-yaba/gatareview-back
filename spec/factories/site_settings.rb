# frozen_string_literal: true

FactoryBot.define do
  factory :site_setting do
    lecture_review_restriction_enabled { false }
    last_updated_by { nil }
  end
end
