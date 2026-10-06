# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Review access during setting failures', type: :request do
  let(:lecture) { create(:lecture) }
  let(:user) { create(:user) }
  let(:restricted_content) { "#{'あ' * 30}設定障害時にも公開されてはいけないレビュー本文" }
  let!(:public_review) { create(:review, lecture: lecture, content: '通常どおり先頭の公開レビューとして読むことができる本文です。', created_at: 2.days.ago) }
  let!(:restricted_review) { create(:review, lecture: lecture, content: restricted_content, created_at: 1.day.ago) }
  let(:headers) { { 'Authorization' => "Bearer #{JsonWebToken.encode(user.jwt_payload)}" } }

  def expect_restricted_response
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('access')).to eq('restriction_enabled' => true, 'access_granted' => false)
    expect(response.parsed_body.fetch('reviews').first.fetch('content')).to eq(public_review.content)
    expect(response.parsed_body.fetch('reviews').last.fetch('content')).to eq('あ' * 30)
    expect(response.body).not_to include('設定障害時にも公開されてはいけない')
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'keeps anonymous readers restricted when the settings query fails' do
    allow(SiteSetting).to receive(:current).and_raise(ActiveRecord::StatementInvalid, 'synthetic settings query failure')

    get "/api/v1/lectures/#{lecture.id}/reviews"

    expect_restricted_response
  end

  it 'keeps anonymous readers restricted when the settings table is unavailable' do
    allow(SiteSetting).to receive(:table_ready?).and_return(false)

    get "/api/v1/lectures/#{lecture.id}/reviews"

    expect_restricted_response
  end

  it 'keeps signed-in readers without a review restricted during a settings failure' do
    allow(SiteSetting).to receive(:current).and_raise(ActiveRecord::StatementInvalid, 'synthetic settings query failure')

    get "/api/v1/lectures/#{lecture.id}/reviews", headers: headers

    expect_restricted_response
  end

  it 'preserves access for readers who meet the posting requirement during a settings failure' do
    create(:review, user: user)
    allow(SiteSetting).to receive(:current).and_raise(ActiveRecord::StatementInvalid, 'synthetic settings query failure')

    get "/api/v1/lectures/#{lecture.id}/reviews", headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('access')).to eq('restriction_enabled' => true, 'access_granted' => true)
    expect(response.parsed_body.fetch('reviews').last.fetch('content')).to eq(restricted_content)
  end

  it 'uses one settings read for both access fields when the setting changes' do
    enabled = SiteSetting.new(lecture_review_restriction_enabled: true)
    disabled = SiteSetting.new(lecture_review_restriction_enabled: false)
    allow(SiteSetting).to receive(:current).and_return(enabled, disabled)

    get "/api/v1/lectures/#{lecture.id}/reviews"

    expect_restricted_response
    expect(SiteSetting).to have_received(:current).once
  end

  it 'preserves the normal unrestricted response when a healthy setting is off' do
    SiteSetting.current!.update!(lecture_review_restriction_enabled: false)

    get "/api/v1/lectures/#{lecture.id}/reviews"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('access')).to eq('restriction_enabled' => false, 'access_granted' => true)
    expect(response.parsed_body.fetch('reviews').last.fetch('content')).to eq(restricted_content)
  end
end
