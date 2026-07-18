# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::TimetablesController, type: :request do
  include ActiveSupport::Testing::TimeHelpers

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
    }, as: :json

    expect(response).to have_http_status(:created)
    expect(user.timetable_entries.count).to eq(2)
    expect(user.timetable_entries.pluck(:lecture_offering_id)).to all(be_nil)

    get '/api/v1/timetable', params: { year: 2026, term: 1 }
    entry_json = JSON.parse(response.body).fetch('entries').first
    expect(entry_json).to include('year' => 2026, 'term' => 1)
    expect(entry_json.dig('lecture', 'id')).to eq(lecture.id)
  end

  it 'links only an explicitly selected active offering for the lecture and year' do
    offering = LectureOffering.create!(
      lecture: lecture,
      year: 2026,
      registration_code: '261H2101',
      shozoku_code: '01'
    )

    post '/api/v1/timetable/entries', params: {
      lecture_id: lecture.id,
      lecture_offering_id: offering.id,
      year: 2026,
      placements: [{ term: 1, day: 1, period: 2 }]
    }, as: :json

    expect(response).to have_http_status(:created)
    expect(user.timetable_entries.last.lecture_offering_id).to eq(offering.id)
  end

  it 'keeps a missing offering reference as provenance and returns its status' do
    offering = LectureOffering.create!(
      lecture: lecture,
      year: 2026,
      registration_code: '261H2103',
      shozoku_code: '01'
    )
    entry = FactoryBot.create(
      :timetable_entry,
      user: user,
      lecture: lecture,
      lecture_offering: offering,
      year: 2026,
      term: 1,
      day: 1,
      period: 2
    )
    offering.update!(source_status: 'missing')

    get '/api/v1/timetable', params: { year: 2026, term: 1 }

    entry_json = JSON.parse(response.body).fetch('entries').first
    expect(entry_json).to include(
      'id' => entry.id,
      'lecture_offering_id' => offering.id,
      'lecture_offering_status' => 'missing'
    )
    expect(entry.reload.lecture_offering_id).to eq(offering.id)
  end

  it 'rejects an explicit offering that belongs to a different lecture or year' do
    other_offering = LectureOffering.create!(
      lecture: FactoryBot.create(:lecture, title: '別講義'),
      year: 2026,
      registration_code: '261H2102',
      shozoku_code: '01'
    )

    post '/api/v1/timetable/entries', params: {
      lecture_id: lecture.id,
      lecture_offering_id: other_offering.id,
      year: 2026,
      placements: [{ term: 1, day: 1, period: 2 }]
    }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.timetable_entries).to be_empty
    expect(JSON.parse(response.body).fetch('errors')).to include('開講情報が講義または年度と一致しません')
  end

  it 'rejects an explicitly selected offering that is no longer active' do
    offering = LectureOffering.create!(
      lecture: lecture,
      year: 2026,
      registration_code: '261H2104',
      shozoku_code: '01',
      source_status: 'missing'
    )

    post '/api/v1/timetable/entries', params: {
      lecture_id: lecture.id,
      lecture_offering_id: offering.id,
      year: 2026,
      placements: [{ term: 1, day: 1, period: 2 }]
    }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.timetable_entries).to be_empty
  end

  it 'returns the current users available years without exposing another users years' do
    FactoryBot.create(:timetable_entry, user: user, year: 2024, term: 1, day: 1, period: 1)
    FactoryBot.create(:timetable_entry, user: user, year: 2026, term: 2, day: 2, period: 2)
    FactoryBot.create(:timetable_entry, user: FactoryBot.create(:user), year: 2020, term: 1, day: 3, period: 3)

    get '/api/v1/timetable', params: { year: 2026, term: 2 }

    json = JSON.parse(response.body)
    expect(json.fetch('available_years')).to eq([2026, 2024])
    expect(json.fetch('entries').first).to include('year' => 2026, 'term' => 2)
  end

  it 'marks a lecture reviewed by the current user despite the legacy string lecture id' do
    FactoryBot.create(:timetable_entry, user: user, lecture: lecture, year: 2026, term: 1, day: 1, period: 2)
    FactoryBot.create(:review, user: user, lecture: lecture)

    get '/api/v1/timetable', params: { year: 2026, term: 1 }

    lecture_json = JSON.parse(response.body).fetch('entries').first.fetch('lecture')
    expect(lecture_json).to include('id' => lecture.id, 'reviewed_by_me' => true)
  end

  it 'returns a conflict and replaces only the current users entry on request' do
    existing = FactoryBot.create(:timetable_entry, user: user, year: 2026, term: 1, day: 1, period: 2)
    request_params = { lecture_id: lecture.id, year: 2026, placements: [{ term: 1, day: 1, period: 2 }] }

    post '/api/v1/timetable/entries', params: request_params, as: :json
    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body).fetch('conflicts').first).to include(
      'id' => existing.id,
      'year' => 2026,
      'term' => 1,
      'day' => 1,
      'period' => 2
    )

    post '/api/v1/timetable/entries', params: request_params.merge(replace: true), as: :json
    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)).to include('conflict_state_changed' => true)
    expect(existing.reload).to be_persisted

    post '/api/v1/timetable/entries', params: request_params.merge(replace: true, conflict_ids: ['invalid']), as: :json
    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)).to include('conflict_state_changed' => true)
    expect(existing.reload).to be_persisted

    post '/api/v1/timetable/entries', params: request_params.merge(replace: true, conflict_ids: [existing.id]), as: :json
    expect(response).to have_http_status(:created)
    expect(TimetableEntry.find_by(id: existing.id)).to be_nil
    expect(user.timetable_entries.find_by!(term: 1, day: 1, period: 2).lecture).to eq(lecture)
  end

  it 'accepts string numbers in a JSON request' do
    post '/api/v1/timetable/entries', params: {
      lecture_id: lecture.id,
      year: '2026',
      placements: [{ term: '1', day: '1', period: '2' }]
    }, as: :json

    expect(response).to have_http_status(:created)
    expect(user.timetable_entries.last).to have_attributes(year: 2026, term: 1, day: 1, period: 2)
  end

  it 'rejects every placement when one item in a JSON request is invalid' do
    post '/api/v1/timetable/entries', params: {
      lecture_id: lecture.id,
      year: 2026,
      placements: [
        { term: 1, day: 1, period: 2 },
        'invalid placement'
      ]
    }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.timetable_entries).to be_empty
  end

  it 'returns the previous academic year during January through March' do
    travel_to Time.utc(2027, 2, 15, 3, 0, 0) do
      get '/api/v1/timetable'

      expect(JSON.parse(response.body)).to include('year' => 2026, 'term' => 4)
    end
  end

  it 'uses the Japan date at the UTC boundary when selecting the academic year' do
    travel_to Time.utc(2026, 3, 31, 15, 30, 0) do
      get '/api/v1/timetable'

      expect(JSON.parse(response.body)).to include('year' => 2026, 'term' => 1)
    end
  end

  it 'does not replace a conflict that changed after confirmation' do
    old_entry = FactoryBot.create(:timetable_entry, user: user, year: 2026, term: 1, day: 1, period: 2)
    request_params = { lecture_id: lecture.id, year: 2026, placements: [{ term: 1, day: 1, period: 2 }] }

    post '/api/v1/timetable/entries', params: request_params, as: :json
    expect(response).to have_http_status(:conflict)

    old_entry.destroy!
    replacement = FactoryBot.create(:timetable_entry, user: user, year: 2026, term: 1, day: 1, period: 2)

    post '/api/v1/timetable/entries', params: request_params.merge(replace: true, conflict_ids: [old_entry.id]), as: :json

    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)).to include('conflict_state_changed' => true)
    expect(JSON.parse(response.body).fetch('conflicts').map { |conflict| conflict.fetch('id') }).to eq([replacement.id])
    expect(replacement.reload).to be_persisted
  end

  it 'returns conflict instead of 500 when the database detects a concurrent insert' do
    allow_any_instance_of(TimetableEntry).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique.new('duplicate slot'))

    post '/api/v1/timetable/entries', params: {
      lecture_id: lecture.id,
      year: 2026,
      placements: [{ term: 1, day: 1, period: 2 }]
    }, as: :json

    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)).to include('conflict_state_changed' => true)
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
