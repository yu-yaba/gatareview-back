# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TimetableEntry do
  let(:user) { FactoryBot.create(:user) }
  let(:lecture) { FactoryBot.create(:lecture) }

  it 'allows intensive entries without a day or period' do
    entry = described_class.new(user: user, lecture: lecture, year: 2026, term: 0)

    expect(entry).to be_valid
  end

  it 'requires a day and period for normal terms' do
    entry = described_class.new(user: user, lecture: lecture, year: 2026, term: 1)

    expect(entry).not_to be_valid
    expect(entry.errors.attribute_names).to include(:day, :period)
  end

  it 'allows a manual placement without an offering reference' do
    entry = described_class.create!(user: user, lecture: lecture, year: 2026, term: 1, day: 1, period: 2)

    expect(entry.lecture_offering_id).to be_nil
  end

  it 'rejects an offering for another lecture' do
    offering = LectureOffering.create!(
      lecture: FactoryBot.create(:lecture, title: '別講義'),
      year: 2026,
      registration_code: '261H2201',
      shozoku_code: '01'
    )
    entry = described_class.new(
      user: user,
      lecture: lecture,
      lecture_offering: offering,
      year: 2026,
      term: 1,
      day: 1,
      period: 2
    )

    expect(entry).not_to be_valid
    expect(entry.errors[:lecture_offering]).to include('は講義と一致しません')
  end

  it 'does not allow two lectures in the same slot' do
    FactoryBot.create(:timetable_entry, user: user, year: 2026, term: 1, day: 1, period: 2)
    duplicate = described_class.new(user: user, lecture: lecture, year: 2026, term: 1, day: 1, period: 2)

    expect(duplicate).not_to be_valid
  end
end
