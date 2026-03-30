# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::LecturesController, type: :request do
  describe 'GET /api/v1/lectures' do
    context '講義が存在する場合' do
      let!(:lecture) { FactoryBot.create(:lecture) }
      let!(:review) { FactoryBot.create(:review, lecture: lecture) }

      it '講義一覧を取得できること' do
        get '/api/v1/lectures'

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['lectures'].first['title']).to eq(lecture.title)
        expect(json['lectures'].first['lecturer']).to eq(lecture.lecturer)
        expect(json['lectures'].first['faculty']).to eq(lecture.faculty)
        expect(json['lectures'].first['avg_rating']).to be_present
        expect(json['lectures'].first['review_count']).to eq(1)
        expect(json['pagination']).to be_present
      end
    end

    context '講義が存在しない場合' do
      it '空配列を返すこと' do
        get '/api/v1/lectures'

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['lectures']).to eq([])
        expect(json['pagination']).to include('current_page' => 1, 'total_count' => 0)
      end
    end
  end

  describe 'GET /api/v1/lectures/:id' do
    let!(:lecture) { FactoryBot.create(:lecture) }

    context '指定したIDの講義が存在する場合' do
      it '講義の詳細を取得できること' do
        get "/api/v1/lectures/#{lecture.id}"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['title']).to eq(lecture.title)
        expect(json['lecturer']).to eq(lecture.lecturer)
        expect(json['faculty']).to eq(lecture.faculty)
      end
    end

    context '指定したIDの講義が存在しない場合' do
      it 'エラーを返すこと' do
        get '/api/v1/lectures/0'

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/lectures/no_reviews' do
    let!(:lectures_without_reviews) { FactoryBot.create_list(:lecture, 6) }
    let!(:reviewed_lecture) { FactoryBot.create(:lecture) }
    let!(:review) { FactoryBot.create(:review, lecture: reviewed_lecture) }

    it 'レビュー未投稿の講義のみを軽量ランダムで返すこと' do
      allow(SecureRandom).to receive(:random_number).with(3).and_return(1)

      get '/api/v1/lectures/no_reviews'

      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      lecture_ids = json.fetch('lectures').map { |lecture_json| lecture_json.fetch('id') }

      expect(lecture_ids).to eq(lectures_without_reviews.map(&:id)[1, 4])
      expect(lecture_ids).not_to include(reviewed_lecture.id)
    end
  end

  describe 'POST /api/v1/lectures' do
    let(:admin_user) { FactoryBot.create(:user, email: 'admin@example.com') }
    let(:valid_params) do
      {
        lecture: {
          title: '新しい講義',
          lecturer: '新しい講師',
          faculty: '新しい学部'
        }
      }
    end

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('ADMIN_EMAILS', '').and_return('admin@example.com')
      allow(ENV).to receive(:fetch).with('ADMIN_EMAIL', nil).and_return(nil)
      allow(AuthorizeApiRequest).to receive(:call).and_return({ result: admin_user })
    end

    context '有効なパラメータの場合' do
      it '講義を作成できること' do
        expect do
          post '/api/v1/lectures', params: valid_params
        end.to change(Lecture, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['title']).to eq('新しい講義')
        expect(json['lecturer']).to eq('新しい講師')
        expect(json['faculty']).to eq('新しい学部')
      end
    end

    context '無効なパラメータの場合' do
      it '講義を作成できないこと' do
        invalid_params = {
          lecture: {
            title: '',
            lecturer: '新しい講師',
            faculty: '新しい学部'
          }
        }

        expect do
          post '/api/v1/lectures', params: invalid_params
        end.not_to change(Lecture, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
