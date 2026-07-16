# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TimetableEntry do
  let(:user) { create(:user) }
  let(:lecture) { create(:lecture) }

  it 'allows intensive entries without a day or period' do
    entry = described_class.new(user: user, lecture: lecture, year: 2026, term: 0)

    expect(entry).to be_valid
  end

  it 'requires a day and period for normal terms' do
    entry = described_class.new(user: user, lecture: lecture, year: 2026, term: 1)

    expect(entry).not_to be_valid
    expect(entry.errors.attribute_names).to include(:day, :period)
  end

  it 'does not allow two lectures in the same slot' do
    create(:timetable_entry, user: user, year: 2026, term: 1, day: 1, period: 2)
    duplicate = described_class.new(user: user, lecture: lecture, year: 2026, term: 1, day: 1, period: 2)

    expect(duplicate).not_to be_valid
  end
end
