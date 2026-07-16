# frozen_string_literal: true

FactoryBot.define do
  factory :timetable_entry do
    association :user
    association :lecture
    year { 2026 }
    term { 1 }
    day { 1 }
    period { 1 }
  end
end
