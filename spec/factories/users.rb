# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name { 'テストユーザー' }
    provider { 'google' }
    sequence(:provider_id) { |n| "google-#{n}" }
    avatar_url { nil }
    reviews_count { 0 }
  end
end

