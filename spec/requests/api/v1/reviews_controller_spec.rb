# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::ReviewsController, type: :request do
  describe 'API input boundaries' do
    let(:user) { FactoryBot.create(:user) }
    let(:lecture) { FactoryBot.create(:lecture) }
    let(:headers) { { 'Authorization' => "Bearer #{JsonWebToken.encode(user.jwt_payload)}" } }
    let(:valid_attributes) { { rating: 3, content: 'あ' * 30 } }

    invalid_attributes = [
      { rating: nil }, { rating: 0 }, { rating: 0.1 }, { rating: 5.5 }, { rating: 999 },
      { rating: 3.3 }, { rating: '5invalid' },
      { content: 'あ' * 29 }, { content: 'あ' * 1001 },
      { textbook: '未定義' }, { attendance: '未定義' }, { grading_type: '未定義' },
      { content_difficulty: '未定義' }, { content_quality: '未定義' }
    ]

    invalid_attributes.each_with_index do |attributes, index|
      it "不正な新規入力を拒否し閲覧権限を付与しないこと（#{index + 1}）" do
        user
        expect do
          post "/api/v1/lectures/#{lecture.id}/reviews", params: { review: valid_attributes.merge(attributes) },
                                                       headers: headers, as: :json
        end.not_to change(Review, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(user.reload.reviews_count).to eq(0)
      end
    end

    ['invalid review shape', [{ rating: 3, content: 'あ' * 30 }]].each do |invalid_review|
      it 'オブジェクト以外のレビュー入力を400で拒否すること' do
        expect do
          post "/api/v1/lectures/#{lecture.id}/reviews", params: { review: invalid_review },
                                                       headers: headers, as: :json
        end.not_to change(Review, :count)

        expect(response).to have_http_status(:bad_request)
      end
    end

    [[0.5, 30], [3.5, 30], [5, 1000]].each do |rating, length|
      it "評価#{rating}・本文#{length}文字の境界値を保存すること" do
        post "/api/v1/lectures/#{lecture.id}/reviews", params: { review: { rating: rating, content: 'あ' * length } },
                                                     headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(Review.last).to have_attributes(rating: rating, content: 'あ' * length, user_id: user.id)
        expect(user.reload.reviews_count).to eq(1)
      end
    end

    it '編集でも評価・短文・詳細の不正値を保存しないこと' do
      review = FactoryBot.create(:review, lecture: lecture, user: user)
      original_attributes = review.attributes

      invalid_attributes.each do |attributes|
        patch "/api/v1/reviews/#{review.id}", params: { review: attributes }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(review.reload.attributes).to eq(original_attributes)
      end
    end

    it '保存済みの整数評価を含む正規の編集を受理すること' do
      review = FactoryBot.create(:review, lecture: lecture, user: user)

      patch "/api/v1/reviews/#{review.id}", params: { review: { rating: review.reload.rating, content: 'い' * 30 } },
                                          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(review.reload).to have_attributes(rating: 5.0, content: 'い' * 30)
    end

    it '編集画面の半星評価を新しく設定できること' do
      review = FactoryBot.create(:review, lecture: lecture, user: user)

      [0.5, 3.5].each do |rating|
        patch "/api/v1/reviews/#{review.id}", params: { review: { rating: rating } }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(review.reload.rating).to eq(rating)
      end
    end
  end

  describe 'reCAPTCHA client IP verification' do
    let(:lecture) { FactoryBot.create(:lecture) }

    before do
      allow(Rails.env).to receive(:test?).and_return(false)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('RECAPTCHA_SECRET_KEY').and_return('test-only-recaptcha-secret')
      google_response = { success: true, score: 0.9, action: 'submit', hostname: 'gatareview.com' }.to_json
      allow(HTTParty).to receive(:post).and_return(instance_double(HTTParty::Response, body: google_response))
    end

    { nil => '10.0.0.5', 'web.1' => '198.51.100.10' }.each do |dyno, expected_ip|
      it "偽装ForwardedとClient-IPを使わず#{dyno ? 'Heroku観測IP' : '接続元IP'}を検証に渡すこと" do
        allow(ENV).to receive(:[]).with('DYNO').and_return(dyno)

        post "/api/v1/lectures/#{lecture.id}/reviews", params: {
          review: { rating: 3, content: 'あ' * 30 }, token: 'test-only-recaptcha-token'
        }, headers: {
          'REMOTE_ADDR' => '10.0.0.5',
          'HTTP_X_FORWARDED_FOR' => '203.0.113.41, 198.51.100.10',
          'HTTP_FORWARDED' => 'for=203.0.113.99',
          'HTTP_CLIENT_IP' => '203.0.113.99'
        }, as: :json

        expect(response).to have_http_status(:created)
        expect(HTTParty).to have_received(:post).with(
          'https://www.google.com/recaptcha/api/siteverify',
          body: hash_including(remoteip: expected_ip), timeout: 10
        )
      end
    end

    it '検証先のタイムアウトではレビューを保存せず422で拒否すること' do
      allow(HTTParty).to receive(:post).and_raise(Net::ReadTimeout)

      expect do
        post "/api/v1/lectures/#{lecture.id}/reviews", params: {
          review: { rating: 3, content: 'あ' * 30 }, token: 'test-only-recaptcha-token'
        }, as: :json
      end.not_to change(Review, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'legacy review attributes' do
    let(:user) { FactoryBot.create(:user) }
    let(:lecture) { FactoryBot.create(:lecture) }
    let(:headers) { { 'Authorization' => "Bearer #{JsonWebToken.encode(user.jwt_payload)}" } }
    let(:review_attributes) { { rating: 4.5, content: '従来のレビューAPIの受講時期を文字列のまま保存できることを確認する本文です。' } }

    [['2026', '1ターム'], ['', 'その他・不明']].each do |year, term|
      it "投稿時に年度#{year.inspect}・ターム#{term.inspect}を保存すること" do
        post "/api/v1/lectures/#{lecture.id}/reviews", params: {
          review: review_attributes.merge(period_year: year, period_term: term)
        }, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(Review.last).to have_attributes(lecture_id: lecture.id.to_s, period_year: year, period_term: term, user_id: user.id)
        expect(response.parsed_body.fetch('review').keys & %w[academic_year term_code lecture_offering_id]).to be_empty
      end

      it "編集時に年度#{year.inspect}・ターム#{term.inspect}を保存すること" do
        review = FactoryBot.create(:review, user: user, lecture: lecture)

        patch "/api/v1/reviews/#{review.id}", params: {
          review: { period_year: year, period_term: term }
        }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(review.reload).to have_attributes(period_year: year, period_term: term)
        expect(response.parsed_body.fetch('review').keys & %w[academic_year term_code lecture_offering_id]).to be_empty
      end
    end

    it '投稿者とURLの授業を確定し、追加の関連付け属性を受け付けないこと' do
      other_user = FactoryBot.create(:user)
      other_lecture = FactoryBot.create(:lecture)

      post "/api/v1/lectures/#{lecture.id}/reviews", params: {
        review: review_attributes.merge(user_id: other_user.id, lecture_id: other_lecture.id,
                                        academic_year: 2030, term_code: 'A', lecture_offering_id: 123)
      }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(Review.last).to have_attributes(lecture_id: lecture.id.to_s, user_id: user.id)
      expect(response.parsed_body.fetch('review').keys & %w[academic_year term_code lecture_offering_id]).to be_empty
    end

    it '本人の編集でも投稿者や授業の関連付け属性を変更できないこと' do
      review = FactoryBot.create(:review, user: user, lecture: lecture)
      other_user = FactoryBot.create(:user)
      other_lecture = FactoryBot.create(:lecture)

      patch "/api/v1/reviews/#{review.id}", params: {
        review: { content: review_attributes.fetch(:content), user_id: other_user.id, lecture_id: other_lecture.id,
                  academic_year: 2030, term_code: 'A', lecture_offering_id: 123 }
      }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(review.reload).to have_attributes(lecture_id: lecture.id.to_s, user_id: user.id)
      expect(response.parsed_body.fetch('review').keys & %w[academic_year term_code lecture_offering_id]).to be_empty
    end
  end

  describe 'GET /api/v1/lectures/:lecture_id/reviews' do
    let!(:lecture) { FactoryBot.create(:lecture) }
    let!(:first_review) { FactoryBot.create(:review, lecture: lecture, content: first_content, created_at: 2.days.ago) }
    let!(:second_review) { FactoryBot.create(:review, lecture: lecture, content: second_content, created_at: 1.day.ago) }

    let(:first_content) { 'この授業はとても学びが多く、講義の構成も分かりやすかったです。おすすめです。' }
    let(:second_content) { '課題はやや多いですが、復習になるので結果的に力がつきます。テスト対策も明確でした。' }

    context 'レビュー閲覧制限が無効な場合' do
      it '全レビューを全文で返すこと' do
        get "/api/v1/lectures/#{lecture.id}/reviews"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json['access']).to eq(
          'restriction_enabled' => false,
          'access_granted' => true
        )
        expect(json['reviews'].length).to eq(2)
        expect(json['reviews'][0]['content']).to eq(first_content)
        expect(json['reviews'][1]['content']).to eq(second_content)
      end

      it 'thanks_count を counter cache から返すこと' do
        Thank.create!(user: FactoryBot.create(:user), review: second_review)

        get "/api/v1/lectures/#{lecture.id}/reviews"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(second_review.reload.thanks_count).to eq(1)
        expect(json['reviews'][0]['thanks_count']).to eq(0)
        expect(json['reviews'][1]['thanks_count']).to eq(1)
      end

      it 'site_settings レコードがなくても制限 OFF 扱いで返すこと' do
        expect(SiteSetting.count).to eq(0)

        get "/api/v1/lectures/#{lecture.id}/reviews"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json['access']).to eq(
          'restriction_enabled' => false,
          'access_granted' => true
        )
      end
    end

    context 'レビュー閲覧制限が有効な場合' do
      let!(:site_setting) { FactoryBot.create(:site_setting, lecture_review_restriction_enabled: true) }
      let!(:user) { FactoryBot.create(:user, reviews_count: 1) }

      before do
        allow(AuthorizeApiRequest).to receive(:call).and_return({ result: user })
      end

      it '全レビューを全文で返すこと' do
        get "/api/v1/lectures/#{lecture.id}/reviews"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json['access']).to eq(
          'restriction_enabled' => true,
          'access_granted' => true
        )
        expect(json['reviews'].length).to eq(2)
        expect(json['reviews'][0]['content']).to eq(first_content)
        expect(json['reviews'][1]['content']).to eq(second_content)
      end
    end

    context 'レビュー閲覧制限が有効で未ログインの場合' do
      let!(:site_setting) { FactoryBot.create(:site_setting, lecture_review_restriction_enabled: true) }

      it '先頭レビュー以外をマスクして返すこと' do
        get "/api/v1/lectures/#{lecture.id}/reviews"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json['access']).to eq(
          'restriction_enabled' => true,
          'access_granted' => false
        )
        expect(json['reviews'][0]['content']).to eq(first_content)
        expect(json['reviews'][1]['content']).to eq(second_content[0, 30])
      end
    end

    context 'レビュー閲覧制限が有効で reviews_count が 0 の場合' do
      let!(:site_setting) { FactoryBot.create(:site_setting, lecture_review_restriction_enabled: true) }
      let!(:user) { FactoryBot.create(:user, reviews_count: 0) }

      before do
        allow(AuthorizeApiRequest).to receive(:call).and_return({ result: user })
      end

      it '制限対象として返すこと' do
        get "/api/v1/lectures/#{lecture.id}/reviews"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json['access']).to eq(
          'restriction_enabled' => true,
          'access_granted' => false
        )
        expect(json['reviews'][1]['content']).to eq(second_content[0, 30])
      end
    end

    context 'レビューが 0 件の授業の場合' do
      let!(:empty_lecture) { FactoryBot.create(:lecture) }
      let!(:site_setting) { FactoryBot.create(:site_setting, lecture_review_restriction_enabled: true) }

      it '空配列と access を返すこと' do
        get "/api/v1/lectures/#{empty_lecture.id}/reviews"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json['reviews']).to eq([])
        expect(json['access']).to eq(
          'restriction_enabled' => true,
          'access_granted' => false
        )
      end
    end
  end

  describe 'GET /api/v1/reviews/latest' do
    let!(:lecture) { FactoryBot.create(:lecture, title: '最新レビュー確認授業', lecturer: '最新レビュー教員') }
    let!(:restricted_setting) { FactoryBot.create(:site_setting, lecture_review_restriction_enabled: true) }
    let!(:older_review) do
      FactoryBot.create(:review, lecture: lecture,
                                  content: '最新レビューAPIでは制限ONでも全文が返ることを確認するためのレビューです。',
                                  created_at: 2.days.ago)
    end
    let!(:latest_review) do
      FactoryBot.create(:review, lecture: lecture,
                                  content: '最新レビューAPIの最新レビュー本文です。こちらも全文返却される必要があります。',
                                  created_at: 1.day.ago)
    end

    it 'レビュー閲覧制限 ON でも全文を返すこと' do
      get '/api/v1/reviews/latest'

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json.length).to eq(2)
      expect(json[0]['content']).to eq(latest_review.content)
      expect(json[1]['content']).to eq(older_review.content)
      expect(json[0]['lecture']).to include(
        'id' => lecture.id,
        'title' => '最新レビュー確認授業',
        'lecturer' => '最新レビュー教員'
      )
    end
  end

  describe 'DELETE /api/v1/reviews/:id' do
    let!(:target_lecture) { FactoryBot.create(:lecture) }
    let!(:first_review) do
      FactoryBot.create(:review, lecture: target_lecture,
                                  content: '先頭レビューの本文です。全文表示されることを確認するために長めにしています。',
                                  created_at: 2.days.ago)
    end
    let!(:second_review) do
      FactoryBot.create(:review, lecture: target_lecture,
                                  content: '二件目レビューの本文です。ロック時はマスクされることを確認するために長めにしています。',
                                  created_at: 1.day.ago)
    end
    let!(:user) { FactoryBot.create(:user, reviews_count: 0) }
    let!(:owned_review) { FactoryBot.create(:review, lecture: FactoryBot.create(:lecture), user: user) }

    before do
      user.reload
      allow(AuthorizeApiRequest).to receive(:call).and_return({ result: user })
    end

    context 'レビュー閲覧制限が有効な場合' do
      let!(:site_setting) { FactoryBot.create(:site_setting, lecture_review_restriction_enabled: true) }

      it '最後のレビューを削除すると再度制限対象になること' do
        get "/api/v1/lectures/#{target_lecture.id}/reviews"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(user.reload.reviews_count).to eq(1)
        expect(json['access']).to eq(
          'restriction_enabled' => true,
          'access_granted' => true
        )

        delete "/api/v1/reviews/#{owned_review.id}"

        expect(response).to have_http_status(:success)
        expect(user.reload.reviews_count).to eq(0)

        get "/api/v1/lectures/#{target_lecture.id}/reviews"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['access']).to eq(
          'restriction_enabled' => true,
          'access_granted' => false
        )
        expect(json['reviews'][0]['content']).to eq('先頭レビューの本文です。全文表示されることを確認するために長めにしています。')
        expect(json['reviews'][1]['content']).to eq('二件目レビューの本文です。ロック時はマスクされることを確認するために長めにしています。'[0, 30])
      end
    end

    context 'レビュー閲覧制限が無効な場合' do
      let!(:site_setting) { FactoryBot.create(:site_setting, lecture_review_restriction_enabled: false) }

      it '最後のレビューを削除しても全文閲覧できること' do
        get "/api/v1/lectures/#{target_lecture.id}/reviews"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(user.reload.reviews_count).to eq(1)
        expect(json['access']).to eq(
          'restriction_enabled' => false,
          'access_granted' => true
        )

        delete "/api/v1/reviews/#{owned_review.id}"

        expect(response).to have_http_status(:success)
        expect(user.reload.reviews_count).to eq(0)

        get "/api/v1/lectures/#{target_lecture.id}/reviews"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['access']).to eq(
          'restriction_enabled' => false,
          'access_granted' => true
        )
        expect(json['reviews'][0]['content']).to eq('先頭レビューの本文です。全文表示されることを確認するために長めにしています。')
        expect(json['reviews'][1]['content']).to eq('二件目レビューの本文です。ロック時はマスクされることを確認するために長めにしています。')
      end
    end
  end
end
