# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::ReviewsController, type: :request do
  describe 'GET /api/v1/lectures/:lecture_id/reviews' do
    let!(:lecture) { FactoryBot.create(:lecture) }
    let!(:first_review) { FactoryBot.create(:review, lecture: lecture, content: first_content, created_at: 2.days.ago) }
    let!(:second_review) { FactoryBot.create(:review, lecture: lecture, content: second_content, created_at: 1.day.ago) }

    let(:first_content) { 'この授業はとても学びが多く、講義の構成も分かりやすかったです。おすすめです。' }
    let(:second_content) { '課題はやや多いですが、復習になるので結果的に力がつきます。テスト対策も明確でした。' }

    context 'レビュー閲覧権限がない場合' do
      it '先頭レビューは全文、それ以外は先頭30文字のみ返すこと' do
        get "/api/v1/lectures/#{lecture.id}/reviews"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json.length).to eq(2)
        expect(json[0]['access_granted']).to eq(false)
        expect(json[0]['content']).to eq(first_content)
        expect(json[1]['access_granted']).to eq(false)
        expect(json[1]['content']).to eq(second_content[0, 30])
      end
    end

    context 'レビュー閲覧権限がある場合' do
      let!(:user) { FactoryBot.create(:user, reviews_count: 1) }

      before do
        allow(AuthorizeApiRequest).to receive(:call).and_return({ result: user })
        allow(ReviewPeriod).to receive(:current_period).and_return(nil)
      end

      it '全レビューを全文で返すこと' do
        get "/api/v1/lectures/#{lecture.id}/reviews"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json.length).to eq(2)
        expect(json[0]['access_granted']).to eq(true)
        expect(json[0]['content']).to eq(first_content)
        expect(json[1]['access_granted']).to eq(true)
        expect(json[1]['content']).to eq(second_content)
      end
    end
  end
end
