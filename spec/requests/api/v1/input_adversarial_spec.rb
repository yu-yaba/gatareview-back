# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API adversarial input boundaries', type: :request do
  let(:lecture) { create(:lecture) }
  let(:valid_review) { { rating: 4.5, content: '正常なレビュー本文です。' * 4, period_year: '2026', period_term: '第1学期' } }

  around do |example|
    keys = %w[action_dispatch.show_exceptions action_dispatch.show_detailed_exceptions]
    original = Rails.application.env_config.slice(*keys)
    Rails.application.env_config['action_dispatch.show_exceptions'] = :all
    Rails.application.env_config['action_dispatch.show_detailed_exceptions'] = false
    example.run
  ensure
    Rails.application.env_config.merge!(original)
  end

  describe 'lecture search' do
    %i[
      page search faculty sort period_year period_term academic_year review_term_code
      textbook attendance grading_type content_difficulty content_quality term day
      period offering_year credits target_year campus language delivery_method subject_category
    ].each do |attribute|
      [['unexpected'], { unexpected: 'value' }].each do |value|
        it "rejects #{attribute} supplied as #{value.class} without a server error" do
          get '/api/v1/lectures', params: { attribute => value }

          expect(response).to have_http_status(:bad_request)
          expect(response.body).not_to include('Mysql2', 'NoMethodError', '/app/')
        end
      end
    end

    it 'rejects a page offset exceeding the database integer range' do
      get '/api/v1/lectures', params: { page: '9' * 100 }

      expect(response).to have_http_status(:bad_request)
    end

    it 'keeps benign page values compatible while rejecting malformed and excessive pages' do
      { '-1' => :ok, '0' => :ok, 'text' => :bad_request, '1e309' => :bad_request,
        '10000' => :ok, '10001' => :bad_request }.each do |page, status|
        get '/api/v1/lectures', params: { page: page }

        expect(response).to have_http_status(status)
      end
    end

    it 'rejects a long search before building the database query' do
      expect(Lecture).not_to receive(:canonical)

      get '/api/v1/lectures', params: { search: 'x' * 8192 }

      expect(response).to have_http_status(:bad_request)
    end

    it 'treats SQL syntax and wildcard characters as literal search text' do
      lecture
      ["' OR 1=1 --", '%', '_', "'; DROP TABLE reviews; --"].each do |search|
        get '/api/v1/lectures', params: { search: search }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.fetch('lectures')).to be_empty
      end
      expect(Lecture.count).to eq(1)
      expect(Review.count).to eq(0)
    end

    it 'keeps SQL fragments in sort, faculty and review-detail filters inert' do
      lecture
      %i[sort faculty textbook period_term].each do |attribute|
        get '/api/v1/lectures', params: { attribute => "' OR 1=1; DROP TABLE reviews; --" }

        expect(response).to have_http_status(:ok)
      end
      expect(Lecture.count).to eq(1)
      expect(Review.count).to eq(0)
    end

    it 'rejects excessively nested query parameters before performing a search' do
      get "/api/v1/lectures?unexpected#{'%5Bnested%5D' * 256}=value"

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'review creation' do
    [nil, [], 'invalid'].each do |root|
      it "rejects a #{root.class} review root" do
        post "/api/v1/lectures/#{lecture.id}/reviews", params: { review: root }, as: :json

        expect(response).to have_http_status(:bad_request)
        expect(Review.count).to eq(0)
      end
    end

    %w[period_year period_term].each do |attribute|
      it "rejects an overlong #{attribute} before writing to MySQL" do
        post "/api/v1/lectures/#{lecture.id}/reviews",
             params: { review: valid_review.merge(attribute => 'x' * 256) }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Review.count).to eq(0)
      end
    end

    ['NaN', 'Infinity', '-Infinity', '1e309', '0.6', '999999999999999999999999'].each do |rating|
      it "rejects the invalid rating #{rating.inspect}" do
        post "/api/v1/lectures/#{lecture.id}/reviews", params: { review: valid_review.merge(rating: rating) }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Review.count).to eq(0)
      end
    end

    [29, 1001].each do |length|
      it "rejects content of #{length} characters" do
        post "/api/v1/lectures/#{lecture.id}/reviews", params: { review: valid_review.merge(content: 'あ' * length) }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Review.count).to eq(0)
      end
    end

    it 'handles malformed JSON without returning a stack trace or writing a review' do
      post "/api/v1/lectures/#{lecture.id}/reviews",
           params: '{"review":', headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:bad_request)
      expect(response.body).not_to include('/app/', 'Mysql2', 'backtrace')
      expect(Review.count).to eq(0)
    end

    it 'rejects excessively nested JSON without writing a review' do
      body = "{\"review\":#{'[' * 256}null#{']' * 256}}"
      post "/api/v1/lectures/#{lecture.id}/reviews", params: body, headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:bad_request)
      expect(Review.count).to eq(0)
    end

    it 'rejects a malformed review root before spending an external CAPTCHA verification' do
      allow(Rails.env).to receive(:test?).and_return(false)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('RECAPTCHA_SECRET_KEY').and_return('fake-adversarial-secret')
      expect(HTTParty).not_to receive(:post)

      post "/api/v1/lectures/#{lecture.id}/reviews", params: { review: [], token: 'fake-token' }, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it 'discards nested content and rating values instead of treating them as valid scalar input' do
      post "/api/v1/lectures/#{lecture.id}/reviews",
           params: { review: valid_review.merge(content: { injected: 'text' }, rating: [4.5]) }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Review.count).to eq(0)
    end
  end

  describe 'review update' do
    it 'preserves the stored review when legacy label input exceeds the database limit' do
      user = create(:user)
      review = create(:review, user: user, lecture: lecture)
      original = review.attributes
      headers = { 'Authorization' => "Bearer #{JsonWebToken.encode(user.jwt_payload)}" }

      patch "/api/v1/reviews/#{review.id}", params: { review: { period_term: 'x' * 256 } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(review.reload.attributes).to eq(original)
    end
  end

  describe 'private file boundaries' do
    it 'does not expose a private canary through file-like or traversal paths' do
      canary = 'adversarial-private-canary-fake-value'
      canary_path = Rails.root.join('tmp', 'adversarial-private-canary.txt')
      File.write(canary_path, canary)
      paths = ['/.env', '/.git/config', '/config/master.key', '/backup.sql', '/output/backup.sql',
               '/tmp/adversarial-private-canary.txt', '/%2e%2e/tmp/adversarial-private-canary.txt']

      paths.each do |path|
        get path

        expect(response.status).to be < 500
        expect(response.body).not_to include(canary)
      end
    ensure
      File.delete(canary_path) if canary_path&.exist?
    end
  end
end
