# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::ReviewsController, type: :request do
  describe 'POST /api/v1/lectures/:lecture_id/reviews' do
    let(:lecture) { FactoryBot.create(:lecture) }
    let(:review_params) do
      {
        rating: 5,
        content: '過年度の開講情報を指定して投稿するレビューです。',
        academic_year: 2025,
        term_code: 'C'
      }
    end
    let(:offering) do
      LectureOffering.create!(
        lecture: lecture,
        year: 2025,
        registration_code: '251H2301',
        shozoku_code: '01',
        term_code: 'C'
      )
    end

    it '指定したactiveな開講情報をレビューに保存すること' do
      post "/api/v1/lectures/#{lecture.id}/reviews", params: {
        review: review_params.merge(lecture_offering_id: offering.id)
      }

      expect(response).to have_http_status(:created)
      expect(Review.last).to have_attributes(
        lecture_id: lecture.id.to_s,
        lecture_offering_id: offering.id,
        academic_year: 2025,
        term_code: 'C'
      )
    end

    it '明示Offeringから変換表外の年度・タームを補完して保存すること' do
      semester_offering = LectureOffering.create!(
        lecture: lecture,
        year: 2026,
        registration_code: '261H2305',
        shozoku_code: '01',
        term_code: '1'
      )

      post "/api/v1/lectures/#{lecture.id}/reviews", params: {
        review: {
          rating: 5,
          content: '第1学期の開講情報を指定して投稿するレビューです。',
          period_year: '不明',
          period_term: '不明',
          lecture_offering_id: semester_offering.id
        }
      }

      expect(response).to have_http_status(:created)
      expect(Review.last).to have_attributes(
        lecture_offering_id: semester_offering.id,
        academic_year: 2026,
        term_code: '1'
      )
    end

    it '別講義・missing・存在しない開講情報を拒否すること' do
      other_offering = LectureOffering.create!(
        lecture: FactoryBot.create(:lecture, title: 'レビュー対象外講義'),
        year: 2025,
        registration_code: '251H2302',
        shozoku_code: '01',
        term_code: 'C'
      )
      missing_offering = LectureOffering.create!(
        lecture: lecture,
        year: 2025,
        registration_code: '251H2303',
        shozoku_code: '01',
        term_code: 'C',
        source_status: 'missing'
      )

      [other_offering.id, missing_offering.id, 0].each do |offering_id|
        post "/api/v1/lectures/#{lecture.id}/reviews", params: {
          review: review_params.merge(lecture_offering_id: offering_id)
        }

        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(Review.where(lecture: lecture)).to be_empty
    end
  end

  describe 'PATCH /api/v1/reviews/:id' do
    let(:user) { FactoryBot.create(:user) }
    let(:lecture) { FactoryBot.create(:lecture) }
    let(:offering) do
      LectureOffering.create!(
        lecture: lecture,
        year: 2026,
        registration_code: '261H2304',
        shozoku_code: '01',
        term_code: 'A'
      )
    end
    let(:review) do
      FactoryBot.create(
        :review,
        user: user,
        lecture: lecture,
        lecture_offering: offering,
        academic_year: 2026,
        term_code: 'A'
      )
    end

    before { allow(AuthorizeApiRequest).to receive(:call).and_return({ result: user }) }

    it 'リンク済みOfferingが後からmissingになっても既存リンクを維持して更新できること' do
      review
      offering.update!(source_status: 'missing')

      patch "/api/v1/reviews/#{review.id}", params: {
        review: { content: '開講終了後に更新したレビュー本文です。' }
      }

      expect(response).to have_http_status(:success)
      expect(review.reload).to have_attributes(
        content: '開講終了後に更新したレビュー本文です。',
        lecture_offering_id: offering.id
      )
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
