# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'User data security', type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:lecture) { create(:lecture) }
  let(:other_lecture) { create(:lecture) }
  let(:headers) { { 'Authorization' => "Bearer #{JsonWebToken.encode(user.jwt_payload)}" } }

  describe 'authentication across protected endpoints' do
    %w[
      /api/v1/auth/me /api/v1/mypage /api/v1/mypage/reviews /api/v1/mypage/bookmarks
      /api/v1/timetable /api/v1/admin/review-access
    ].each do |path|
      it "rejects a revoked token at #{path}" do
        issued_headers = headers
        post '/api/v1/auth/logout', headers: issued_headers
        expect(response).to have_http_status(:ok)

        get path, headers: issued_headers

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers['Cache-Control']).to include('no-store')
      end
    end

    it 'rejects malformed and expired JWTs without returning personal data' do
      ['invalid-token', JsonWebToken.encode(user.jwt_payload, 1.minute.ago)].each do |invalid_token|
        get '/api/v1/mypage', headers: { 'Authorization' => "Bearer #{invalid_token}" }

        expect(response).to have_http_status(:unauthorized)
        expect(response.body).not_to include(user.email)
      end
    end

    it 'rejects revoked JWTs for personal mutations before looking up resources' do
      issued_headers = headers
      post '/api/v1/auth/logout', headers: issued_headers
      protected_requests = [
        %w[post /api/v1/lectures/1/bookmarks], %w[get /api/v1/lectures/1/bookmarks],
        %w[delete /api/v1/lectures/1/bookmarks], %w[post /api/v1/reviews/1/thanks],
        %w[get /api/v1/reviews/1/thanks], %w[delete /api/v1/reviews/1/thanks],
        %w[patch /api/v1/reviews/1], %w[delete /api/v1/reviews/1],
        %w[post /api/v1/timetable/entries], %w[delete /api/v1/timetable/entries/1],
        %w[patch /api/v1/admin/review-access], %w[post /api/v1/lectures]
      ]

      protected_requests.each do |method, path|
        send(method, path, headers: issued_headers)

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers['Cache-Control']).to include('no-store')
      end
    end

    it 'uses database privileges instead of admin claims in a JWT' do
      claims = user.jwt_payload.merge(admin: true, email: 'admin@example.com')
      get '/api/v1/admin/review-access', headers: { 'Authorization' => "Bearer #{JsonWebToken.encode(claims)}" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'personal data isolation' do
    it 'ignores another user ID when showing the signed-in users profile and reviews' do
      own_review = create(:review, user: user, lecture: lecture)
      other_review = create(:review, user: other_user, lecture: other_lecture)

      get '/api/v1/mypage', params: { user_id: other_user.id }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('user', 'email')).to eq(user.email)
      expect(response.parsed_body.fetch('user_reviews').pluck('id')).to eq([own_review.id])
      expect(response.body).not_to include(other_user.email)
      expect(response.headers['Cache-Control']).to include('no-store')

      get '/api/v1/mypage/reviews', params: { user_id: other_user.id }, headers: headers
      expect(response.parsed_body.fetch('reviews').pluck('id')).to eq([own_review.id])
      expect(response.parsed_body.fetch('reviews').pluck('id')).not_to include(other_review.id)
    end

    it 'returns only the signed-in users bookmarks' do
      Bookmark.create!(user: user, lecture: lecture)
      Bookmark.create!(user: other_user, lecture: other_lecture)

      get '/api/v1/mypage/bookmarks', params: { user_id: other_user.id }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('bookmarks').pluck('id')).to eq([lecture.id.to_i])
    end

    it 'ignores a supplied user ID when creating a bookmark' do
      post "/api/v1/lectures/#{lecture.id}/bookmarks", params: { user_id: other_user.id }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(lecture.bookmarks.pluck(:user_id)).to eq([user.id])
    end

    it 'cannot delete another users bookmark' do
      bookmark = Bookmark.create!(user: other_user, lecture: lecture)

      delete "/api/v1/lectures/#{lecture.id}/bookmarks", params: { user_id: other_user.id }, headers: headers

      expect(response).to have_http_status(:not_found)
      expect(Bookmark.exists?(bookmark.id)).to be(true)
    end

    it 'ignores a supplied user ID when thanking a review' do
      review = create(:review, user: other_user, lecture: lecture)
      post "/api/v1/reviews/#{review.id}/thanks", params: { user_id: other_user.id }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(review.thanks.pluck(:user_id)).to eq([user.id])
    end

    it 'cannot delete another users thank' do
      review = create(:review, lecture: lecture)
      thank = Thank.create!(user: other_user, review: review)

      delete "/api/v1/reviews/#{review.id}/thanks", params: { user_id: other_user.id }, headers: headers

      expect(response).to have_http_status(:not_found)
      expect(Thank.exists?(thank.id)).to be(true)
    end

    it 'cannot edit or delete another users review' do
      review = create(:review, user: other_user, lecture: lecture)
      original_content = review.content

      patch "/api/v1/reviews/#{review.id}", params: { review: { content: '他人のレビューを書き換えるために送信する不正なリクエストの本文です。' } }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(review.reload.content).to eq(original_content)

      delete "/api/v1/reviews/#{review.id}", headers: headers
      expect(response).to have_http_status(:forbidden)
      expect(Review.exists?(review.id)).to be(true)
    end

    it 'cannot delete another users timetable entry even with all_for_lecture' do
      entry = create(:timetable_entry, user: other_user, lecture: lecture)

      delete "/api/v1/timetable/entries/#{entry.id}", params: { all_for_lecture: true, user_id: other_user.id }, headers: headers

      expect(response).to have_http_status(:not_found)
      expect(TimetableEntry.exists?(entry.id)).to be(true)
    end

    it 'keeps another users timetable out of the response' do
      own_entry = create(:timetable_entry, user: user, lecture: lecture)
      create(:timetable_entry, user: other_user, lecture: other_lecture)

      get '/api/v1/timetable', params: { year: 2026, term: 1, user_id: other_user.id }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('entries').pluck('id')).to eq([own_entry.id])
    end
  end

  describe 'bounded pagination' do
    %w[reviews bookmarks].each do |collection|
      [0, -1, 'invalid', ''].each do |invalid_value|
        it "handles #{collection} page/per_page=#{invalid_value.inspect} without an exception" do
          get "/api/v1/mypage/#{collection}", params: { page: invalid_value, per_page: invalid_value }, headers: headers

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body.dig('pagination', 'current_page')).to eq(1)
          expect(response.parsed_body.dig('pagination', 'per_page')).to eq(10)
        end
      end

      it "limits #{collection} results to at most 50 per page" do
        get "/api/v1/mypage/#{collection}", params: { per_page: 1_000_000 }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('pagination', 'per_page')).to eq(50)
      end
    end
  end
end
