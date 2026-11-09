# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'レビュー・ブックマーク・ありがとうの重複と並び順', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:lecture) { create(:lecture) }
  let(:headers) { { 'Authorization' => "Bearer #{JsonWebToken.encode(user.jwt_payload)}" } }
  let(:review_attributes) do
    { rating: 4, content: 'この授業は板書が丁寧で、毎回の小テストのおかげで復習の習慣がつきました。',
      textbook: '必要', attendance: '毎回確認', grading_type: 'テストのみ', content_difficulty: '普通',
      content_quality: '良い', period_year: '2025', period_term: '前期' }
  end

  def post_review(attributes = review_attributes, request_headers = headers)
    post "/api/v1/lectures/#{lecture.id}/reviews", params: { review: attributes }, headers: request_headers, as: :json
  end

  describe 'POST /api/v1/lectures/:lecture_id/reviews（ログイン投稿）' do
    it '同じ授業への2件目は日本語の文言で422にし、保存しないこと' do
      post_review
      expect(response).to have_http_status(:created)

      expect { post_review(review_attributes.merge(rating: 2)) }.not_to change(Review, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to eq(['この授業にはすでにレビューを投稿しています'])
      expect(user.reload.reviews_count).to eq(1)
    end

    it '同じ内容の再送は新しく作らず、既存のレビューを200で返すこと' do
      post_review
      first_id = response.parsed_body.dig('review', 'id')

      expect { post_review }.not_to change(Review, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('success' => true)
      expect(response.parsed_body['review']).to include('id' => first_id, 'is_own' => true)
      expect(user.reload.reviews_count).to eq(1)
    end

    it '検証をすり抜けた同時投稿も一意インデックスで止め、500ではなく同じ文言の422を返すこと' do
      create(:review, lecture: lecture, user: user, created_at: 1.hour.ago)
      allow_any_instance_of(Review).to receive(:one_review_per_user_and_lecture)

      expect { post_review }.not_to change(Review, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to eq(['この授業にはすでにレビューを投稿しています'])
    end

    it 'デッドロックで巻き戻された投稿を1回だけやり直して保存すること' do
      attempts = 0
      allow_any_instance_of(Review).to receive(:save).and_wrap_original do |original, *args|
        attempts += 1
        raise ActiveRecord::Deadlocked, 'Deadlock found when trying to get lock' if attempts == 1

        original.call(*args)
      end

      expect { post_review }.to change(Review, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(attempts).to eq(2)
      expect(user.reload.reviews_count).to eq(1)
    end
  end

  describe 'POST /api/v1/lectures/:lecture_id/reviews（匿名投稿）' do
    it '同じ内容の再送は新しく作らず、既存のレビューを返すこと' do
      post_review(review_attributes, {})
      expect(response).to have_http_status(:created)
      first_id = response.parsed_body.dig('review', 'id')

      expect { post_review(review_attributes, {}) }.not_to change(Review, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['review']).to include('id' => first_id, 'is_own' => false)
    end

    it '項目が1つでも違えば別の投稿として保存すること' do
      post_review(review_attributes, {})

      expect { post_review(review_attributes.merge(content_quality: '普通'), {}) }.to change(Review, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it '再送とみなす時間を過ぎた同じ内容は新しい投稿として保存すること' do
      post_review(review_attributes, {})

      travel(ReviewSubmission::RETRY_WINDOW + 1.minute) do
        expect { post_review(review_attributes, {}) }.to change(Review, :count).by(1)
      end
      expect(response).to have_http_status(:created)
    end

    it 'ログイン投稿と同じ内容でも匿名投稿を既存のレビューにまとめないこと' do
      post_review

      expect { post_review(review_attributes, {}) }.to change(Review, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(Review.last.user_id).to be_nil
    end
  end

  describe 'PATCH /api/v1/reviews/:id' do
    it 'デッドロックで巻き戻された編集を1回だけやり直して保存すること' do
      review = create(:review, lecture: lecture, user: user)
      attempts = 0
      allow_any_instance_of(Review).to receive(:save).and_wrap_original do |original, *args|
        attempts += 1
        raise ActiveRecord::Deadlocked, 'Deadlock found when trying to get lock' if attempts == 1

        original.call(*args)
      end

      patch "/api/v1/reviews/#{review.id}", params: { review: { rating: 2 } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(review.reload.rating).to eq(2.0)
      expect(attempts).to eq(2)
    end
  end

  describe 'POST /api/v1/lectures/:lecture_id/bookmarks' do
    it '登録済みなら日本語の文言で422にすること' do
      Bookmark.create!(user: user, lecture: lecture)

      post "/api/v1/lectures/#{lecture.id}/bookmarks", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to eq(['この授業はすでにブックマークしています'])
    end

    it '連打で検証をすり抜けた2件目も500ではなく同じ文言の422にすること' do
      Bookmark.create!(user: user, lecture: lecture)
      allow_any_instance_of(Bookmark).to receive(:not_already_bookmarked)

      expect { post "/api/v1/lectures/#{lecture.id}/bookmarks", headers: headers }.not_to change(Bookmark, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to eq(['この授業はすでにブックマークしています'])
    end
  end

  describe 'POST /api/v1/reviews/:review_id/thanks' do
    let(:review) { create(:review, lecture: lecture) }

    it '送信済みなら日本語の文言で422にすること' do
      Thank.create!(user: user, review: review)

      post "/api/v1/reviews/#{review.id}/thanks", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to eq(['このレビューにはすでにありがとうを送っています'])
    end

    it '連打で検証をすり抜けた2件目も500ではなく同じ文言の422にすること' do
      Thank.create!(user: user, review: review)
      allow_any_instance_of(Thank).to receive(:not_already_thanked)

      expect { post "/api/v1/reviews/#{review.id}/thanks", headers: headers }.not_to change(Thank, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to eq(['このレビューにはすでにありがとうを送っています'])
      expect(review.reload.thanks_count).to eq(1)
    end

    it '自分のレビューへのありがとうは日本語の文言で422にすること' do
      own_review = create(:review, lecture: lecture, user: user)

      post "/api/v1/reviews/#{own_review.id}/thanks", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to eq(['自分のレビューにはありがとうできません'])
    end
  end

  describe '投稿時刻が同じレビューの並び順' do
    let(:posted_at) { Time.zone.parse('2026-04-01 09:00:00') }

    def create_reviews_at_same_time(count, **attributes)
      reviews = Array.new(count) { create(:review, **attributes) }
      Review.where(id: reviews.map(&:id)).update_all(created_at: posted_at, updated_at: posted_at)
      reviews
    end

    def review_order_sql
      sql = []
      callback = ->(*, payload) { sql << payload[:sql] if payload[:sql].match?(/FROM `reviews`.*ORDER BY/) }
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { yield }
      sql
    end

    it '授業のレビュー一覧は id でも並べ、全文表示する先頭が読み込みごとに変わらないこと' do
      reviews = create_reviews_at_same_time(3, lecture: lecture)

      sql = review_order_sql { get "/api/v1/lectures/#{lecture.id}/reviews" }

      expect(response.parsed_body['reviews'].pluck('id')).to eq(reviews.map(&:id))
      expect(sql).to include(a_string_matching(/ORDER BY `reviews`.`created_at` ASC, `reviews`.`id` ASC/))
    end

    it '最新レビューは同じ時刻なら id の新しい順に返すこと' do
      reviews = create_reviews_at_same_time(5, lecture: lecture)

      get '/api/v1/reviews/latest'

      expect(response.parsed_body.pluck('id')).to eq(reviews.map(&:id).reverse.first(4))
    end

    it 'マイページのレビュー一覧は同じ時刻なら id の新しい順に、ページをまたいでも重複・欠けなく返すこと' do
      reviews = create_reviews_at_same_time(12, user: user)

      ids = [1, 2].flat_map do |page|
        get '/api/v1/mypage/reviews', params: { page: page, per_page: 10 }, headers: headers
        response.parsed_body['reviews'].pluck('id')
      end

      expect(ids).to eq(reviews.map(&:id).reverse)
    end

    it 'マイページのレビューと最新レビューは同じ時刻なら id の新しい順に返すこと' do
      reviews = create_reviews_at_same_time(3, user: user)

      get '/api/v1/mypage', headers: headers

      body = response.parsed_body
      expect(body['user_reviews'].pluck('id')).to eq(reviews.map(&:id).reverse)
      expect(body.dig('statistics', 'latest_review', 'id')).to eq(reviews.last.id)
    end
  end
end
