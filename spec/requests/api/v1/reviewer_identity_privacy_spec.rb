# frozen_string_literal: true

require 'rails_helper'

# 画面に投稿者を表示していないため、公開レビュー API から投稿者を特定・名寄せできる値
# （Google の表示名、プロフィール画像 URL、ユーザー ID）を返さないことを保証する。
RSpec.describe 'Reviewer identity privacy', type: :request do
  public_review_keys = %w[
    id rating content lecture_id textbook attendance grading_type content_difficulty content_quality
    period_year period_term created_at updated_at thanks_count is_own
  ].freeze

  let!(:owner) do
    create(:user, name: '投稿者本人オーナー', avatar_url: 'https://lh3.googleusercontent.com/a/owner-avatar-marker')
  end
  let!(:other_reviewer) do
    create(:user, name: '別の投稿者マーカー', avatar_url: 'https://lh3.googleusercontent.com/a/other-avatar-marker')
  end
  let!(:viewer) do
    create(:user, name: '閲覧者マーカー', avatar_url: 'https://lh3.googleusercontent.com/a/viewer-avatar-marker')
  end
  let!(:lecture) { create(:lecture) }
  let!(:owner_review) { create(:review, lecture: lecture, user: owner, created_at: 3.days.ago) }
  let!(:other_review) { create(:review, lecture: lecture, user: other_reviewer, created_at: 2.days.ago) }
  let!(:anonymous_review) { create(:review, lecture: lecture, user: nil, created_at: 1.day.ago) }

  let(:identity_markers) do
    [owner, other_reviewer, viewer].flat_map { |user| [user.name, user.avatar_url, user.email] } + ['匿名ユーザー']
  end

  def auth_headers(user)
    { 'Authorization' => "Bearer #{JsonWebToken.encode(user.jwt_payload)}" }
  end

  def expect_no_identity_in_body
    identity_markers.each { |marker| expect(response.body).not_to include(marker) }
    expect(response.body).not_to include('avatar_url')
    expect(response.body).not_to include('user_id')
  end

  describe 'GET /api/v1/lectures/:lecture_id/reviews' do
    [true, false].each do |restriction_enabled|
      context "レビュー閲覧制限が #{restriction_enabled ? 'ON' : 'OFF'} の場合" do
        before { create(:site_setting, lecture_review_restriction_enabled: restriction_enabled) }

        it '未ログインでは投稿者情報を返さず is_own はすべて false' do
          get "/api/v1/lectures/#{lecture.id}/reviews"

          expect(response).to have_http_status(:ok)
          expect_no_identity_in_body
          reviews = response.parsed_body.fetch('reviews')
          expect(reviews.length).to eq(3)
          reviews.each { |review| expect(review.keys).to match_array(public_review_keys) }
          expect(reviews.pluck('is_own')).to eq([false, false, false])
        end

        it '他人のトークンでは他人の投稿者情報を返さず is_own はすべて false' do
          get "/api/v1/lectures/#{lecture.id}/reviews", headers: auth_headers(viewer)

          expect(response).to have_http_status(:ok)
          expect_no_identity_in_body
          reviews = response.parsed_body.fetch('reviews')
          reviews.each { |review| expect(review.keys).to match_array(public_review_keys) }
          expect(reviews.pluck('is_own')).to eq([false, false, false])
        end

        it '投稿者本人のトークンでは自分のレビューだけ is_own が true で、投稿者情報は返さない' do
          get "/api/v1/lectures/#{lecture.id}/reviews", headers: auth_headers(owner)

          expect(response).to have_http_status(:ok)
          expect_no_identity_in_body
          reviews = response.parsed_body.fetch('reviews')
          reviews.each { |review| expect(review.keys).to match_array(public_review_keys) }
          expect(reviews.to_h { |review| [review['id'], review['is_own']] }).to eq(
            owner_review.id => true, other_review.id => false, anonymous_review.id => false
          )
        end

        it '無効なトークンは未ログイン扱いで is_own はすべて false' do
          get "/api/v1/lectures/#{lecture.id}/reviews", headers: { 'Authorization' => 'Bearer invalid-token' }

          expect(response).to have_http_status(:ok)
          expect_no_identity_in_body
          expect(response.parsed_body.fetch('reviews').pluck('is_own')).to eq([false, false, false])
        end
      end
    end
  end

  describe 'GET /api/v1/reviews/latest' do
    [true, false].each do |restriction_enabled|
      context "レビュー閲覧制限が #{restriction_enabled ? 'ON' : 'OFF'} の場合" do
        before { create(:site_setting, lecture_review_restriction_enabled: restriction_enabled) }

        [nil, :owner, :viewer].each do |requester|
          it "#{requester ? "#{requester} のトークン" : '未ログイン'}でも投稿者情報を返さない" do
            get '/api/v1/reviews/latest', headers: requester ? auth_headers(public_send(requester)) : {}

            expect(response).to have_http_status(:ok)
            expect_no_identity_in_body
            reviews = response.parsed_body
            expect(reviews.pluck('id')).to eq([anonymous_review.id, other_review.id, owner_review.id])
            reviews.each do |review|
              expect(review.keys).to match_array(%w[id rating created_at content lecture])
              expect(review.fetch('lecture').keys).to match_array(%w[id title lecturer faculty])
            end
          end
        end
      end
    end
  end

  describe 'レビュー作成・更新のレスポンス' do
    let(:review_body) { { rating: 4, content: '投稿者情報を含めずに作成・更新結果を返すことを確認するための本文です。' } }

    it 'ログインして作成すると is_own が true で投稿者情報は返さない' do
      other_lecture = create(:lecture)
      post "/api/v1/lectures/#{other_lecture.id}/reviews", params: { review: review_body },
                                                           headers: auth_headers(viewer), as: :json

      expect(response).to have_http_status(:created)
      expect_no_identity_in_body
      review = response.parsed_body.fetch('review')
      expect(review.keys).to match_array(public_review_keys)
      expect(review['is_own']).to be(true)
      expect(Review.find(review['id']).user_id).to eq(viewer.id)
    end

    it '未ログインで作成すると is_own が false で投稿者情報は返さない' do
      post "/api/v1/lectures/#{lecture.id}/reviews", params: { review: review_body }, as: :json

      expect(response).to have_http_status(:created)
      expect_no_identity_in_body
      review = response.parsed_body.fetch('review')
      expect(review.keys).to match_array(public_review_keys)
      expect(review['is_own']).to be(false)
    end

    it '本人が更新すると is_own が true で投稿者情報は返さない' do
      patch "/api/v1/reviews/#{owner_review.id}", params: { review: review_body },
                                                  headers: auth_headers(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect_no_identity_in_body
      review = response.parsed_body.fetch('review')
      expect(review.keys).to match_array(public_review_keys)
      expect(review).to include('id' => owner_review.id, 'is_own' => true, 'content' => review_body[:content])
    end
  end

  describe 'マイページ（本人スコープ）' do
    it '本人のレビューだけを返し続ける' do
      get '/api/v1/mypage/reviews', headers: auth_headers(owner)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('reviews').pluck('id')).to eq([owner_review.id])
      expect(response.body).not_to include(other_reviewer.name)
      expect(response.body).not_to include(other_reviewer.avatar_url)
    end

    it '本人のプロフィールと本人のレビューを返し続ける' do
      get '/api/v1/mypage', headers: auth_headers(owner)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('user', 'name')).to eq(owner.name)
      expect(response.parsed_body.fetch('user_reviews').pluck('id')).to eq([owner_review.id])
      expect(response.body).not_to include(other_reviewer.name)
    end
  end
end
