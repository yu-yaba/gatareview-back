# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::TimetablesController, type: :request do
  let(:user) { FactoryBot.create(:user) }
  let(:lecture) { FactoryBot.create(:lecture) }

  before { allow(AuthorizeApiRequest).to receive(:call).and_return({ result: user }) }

  it 'requires authentication' do
    allow(AuthorizeApiRequest).to receive(:call).and_return({ result: nil })

    get '/api/v1/timetable'

    expect(response).to have_http_status(:unauthorized)
  end

  it 'creates multiple placements and returns them from the timetable' do
    post '/api/v1/timetable/entries', params: {
      lecture_id: lecture.id,
      year: 2026,
      placements: [{ term: 1, day: 1, period: 2 }, { term: 2, day: 1, period: 2 }]
    }

    expect(response).to have_http_status(:created)
    expect(user.timetable_entries.count).to eq(2)

    get '/api/v1/timetable', params: { year: 2026, term: 1 }
    expect(JSON.parse(response.body).fetch('entries').first.dig('lecture', 'id')).to eq(lecture.id)
  end

  it 'returns a conflict and replaces only the current users entry on request' do
    existing = FactoryBot.create(:timetable_entry, user: user, year: 2026, term: 1, day: 1, period: 2)

    post '/api/v1/timetable/entries', params: { lecture_id: lecture.id, year: 2026, placements: [{ term: 1, day: 1, period: 2 }] }
    expect(response).to have_http_status(:conflict)

    post '/api/v1/timetable/entries', params: { lecture_id: lecture.id, year: 2026, placements: [{ term: 1, day: 1, period: 2 }], replace: true }
    expect(response).to have_http_status(:created)
    expect(TimetableEntry.find_by(id: existing.id)).to be_nil
    expect(user.timetable_entries.find_by!(term: 1, day: 1, period: 2).lecture).to eq(lecture)
  end

  it 'only deletes the current users entry' do
    entry = FactoryBot.create(:timetable_entry, user: user)
    other_entry = FactoryBot.create(:timetable_entry, user: FactoryBot.create(:user), day: 2)

    delete "/api/v1/timetable/entries/#{other_entry.id}"
    expect(response).to have_http_status(:not_found)

    delete "/api/v1/timetable/entries/#{entry.id}", params: { all_for_lecture: true }
    expect(response).to have_http_status(:success)
  end
end
