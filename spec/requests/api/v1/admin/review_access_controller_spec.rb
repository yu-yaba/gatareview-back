# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Admin::ReviewAccessController, type: :request do
  let(:admin_user) { FactoryBot.create(:user, email: 'admin@example.com') }
  let(:general_user) { FactoryBot.create(:user) }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('ADMIN_EMAILS', '').and_return('admin@example.com')
    allow(ENV).to receive(:fetch).with('ADMIN_EMAIL', nil).and_return(nil)
  end

  describe 'GET /api/v1/admin/review-access' do
    context '未ログインの場合' do
      it '401 を返すこと' do
        get '/api/v1/admin/review-access'

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context '非管理者の場合' do
      before do
        allow(AuthorizeApiRequest).to receive(:call).and_return({ result: general_user })
      end

      it '403 を返すこと' do
        get '/api/v1/admin/review-access'

        expect(response).to have_http_status(:forbidden)
      end
    end

    context '管理者の場合' do
      before do
        allow(AuthorizeApiRequest).to receive(:call).and_return({ result: admin_user })
      end

      it '現在の設定を返すこと' do
        get '/api/v1/admin/review-access'

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json['lecture_review_restriction_enabled']).to eq(false)
        expect(json['updated_at']).to be_nil
        expect(json['last_updated_by']).to be_nil
      end
    end
  end

  describe 'PATCH /api/v1/admin/review-access' do
    before do
      allow(AuthorizeApiRequest).to receive(:call).and_return({ result: admin_user })
    end

    it '設定を更新すること' do
      patch '/api/v1/admin/review-access', params: {
        review_access: {
          lecture_review_restriction_enabled: true
        }
      }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json['lecture_review_restriction_enabled']).to eq(true)
      expect(json['last_updated_by']).to include(
        'id' => admin_user.id,
        'name' => admin_user.name,
        'email' => admin_user.email
      )
      expect(SiteSetting.current.lecture_review_restriction_enabled).to eq(true)
      expect(SiteSetting.current.last_updated_by).to eq(admin_user)
    end

    it '不正な値では 422 を返すこと' do
      patch '/api/v1/admin/review-access', params: {
        review_access: {
          lecture_review_restriction_enabled: 'invalid'
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
