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
        expect(json.first['title']).to eq(lecture.title)
        expect(json.first['lecturer']).to eq(lecture.lecturer)
        expect(json.first['faculty']).to eq(lecture.faculty)
        expect(json.first['avg_rating']).to be_present
        expect(json.first['reviews']).to be_present
      end
    end

    context '講義が存在しない場合' do
      it 'エラーを返すこと' do
        get '/api/v1/lectures'
        
        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('授業が見つかりません。')
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

  describe 'POST /api/v1/lectures' do
    let(:valid_params) do
      {
        lecture: {
          title: '新しい講義',
          lecturer: '新しい講師',
          faculty: '新しい学部'
        }
      }
    end

    context '有効なパラメータの場合' do
      it '講義を作成できること' do
        expect {
          post '/api/v1/lectures', params: valid_params
        }.to change(Lecture, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['title']).to eq('新しい講義')
        expect(json['lecturer']).to eq('新しい講師')
        expect(json['faculty']).to eq('新しい学部')
      end
    end

    context '無効なパラメータの場合' do
      it '講義を作成できないこと' do
        invalid_params = { lecture: { title: '' } }
        
        expect {
          post '/api/v1/lectures', params: invalid_params
        }.not_to change(Lecture, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end 