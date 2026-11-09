# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::MypageController, type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{JsonWebToken.encode(user.jwt_payload)}" } }

  describe 'GET /api/v1/mypage/bookmarks' do
    context 'ブックマーク日時が同じ授業が多数ある場合' do
      let!(:lectures) { create_list(:lecture, 35) }

      before do
        lectures.each { |lecture| Bookmark.create!(user: user, lecture: lecture) }
        bookmarked_at = Time.zone.parse('2026-04-01 09:00:00')
        Bookmark.update_all(created_at: bookmarked_at, updated_at: bookmarked_at)
      end

      it '全ページを辿ると重複も欠けもなく、新しいブックマーク順に並ぶこと' do
        ids = (1..4).flat_map do |page|
          get '/api/v1/mypage/bookmarks', params: { page: page, per_page: 10 }, headers: headers
          expect(response).to have_http_status(:ok)
          response.parsed_body.fetch('bookmarks').pluck('id')
        end

        expect(ids.tally.select { |_id, count| count > 1 }.keys).to eq([]), '複数ページに重複して表示される授業がある'
        expect(ids).to eq(lectures.map(&:id).reverse)
      end
    end
  end
end
