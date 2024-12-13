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
end 