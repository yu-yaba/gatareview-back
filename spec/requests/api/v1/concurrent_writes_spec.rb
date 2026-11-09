# frozen_string_literal: true

require 'rails_helper'

# 実際に複数のスレッドから同時にリクエストを送り、DB のロック・一意インデックスまで含めて確かめる。
# 別々の接続でコミットが見える必要があるため、テストのトランザクションを使わずに後片付けする。
RSpec.describe '同時に届いた書き込み', type: :request do
  self.use_transactional_tests = false

  let(:concurrency) { 8 }
  let(:user) { create(:user) }
  let(:lecture) { create(:lecture) }
  let(:token) { JsonWebToken.encode(user.jwt_payload) }
  let(:review_attributes) do
    { rating: 4, content: '同時に届いた投稿が1件にまとまるかを確かめるための、三十文字を超えるレビュー本文です。' }
  end

  before { Rails.application.eager_load! }

  after { [Thank, Bookmark, Review, Lecture, User].each(&:delete_all) }

  # 全スレッドが揃ってから一斉に送る。例外は 500 として数える。
  def concurrent_posts(path, bodies:, token: nil)
    gate = Queue.new
    threads = bodies.map do |body|
      Thread.new do
        gate.pop
        headers = { 'CONTENT_TYPE' => 'application/json' }
        headers['HTTP_AUTHORIZATION'] = "Bearer #{token}" if token
        Rack::MockRequest.new(Rails.application).post(path, headers.merge(input: body.to_json)).status
      rescue StandardError => e
        "#{e.class}: #{e.message.lines.first}"
      end
    end
    bodies.size.times { gate << true }
    threads.map(&:value).tally
  end

  it 'ログイン利用者の同じ内容の同時投稿は1件だけ作り、残りは既存のレビューを返すこと' do
    statuses = concurrent_posts("/api/v1/lectures/#{lecture.id}/reviews",
                                bodies: Array.new(concurrency) { { review: review_attributes } }, token: token)

    expect(statuses).to eq(201 => 1, 200 => concurrency - 1)
    expect(Review.where(user: user).count).to eq(1)
    expect(user.reload.reviews_count).to eq(1)
  end

  it 'ログイン利用者の内容の違う同時投稿は1件だけ作り、残りは422にすること' do
    bodies = Array.new(concurrency) do |index|
      { review: review_attributes.merge(content: "#{review_attributes[:content]}#{index}") }
    end

    statuses = concurrent_posts("/api/v1/lectures/#{lecture.id}/reviews", bodies: bodies, token: token)

    expect(statuses).to eq(201 => 1, 422 => concurrency - 1)
    expect(Review.where(user: user).count).to eq(1)
    expect(user.reload.reviews_count).to eq(1)
  end

  it '匿名の同じ内容の同時投稿は1件だけ作ること' do
    statuses = concurrent_posts("/api/v1/lectures/#{lecture.id}/reviews",
                                bodies: Array.new(concurrency) { { review: review_attributes } })

    expect(statuses).to eq(201 => 1, 200 => concurrency - 1)
    expect(Review.where(lecture_id: lecture.id).count).to eq(1)
  end

  it 'ブックマークの連打は1件だけ作り、残りは500ではなく422にすること' do
    statuses = concurrent_posts("/api/v1/lectures/#{lecture.id}/bookmarks",
                                bodies: Array.new(concurrency) { {} }, token: token)

    expect(statuses).to eq(201 => 1, 422 => concurrency - 1)
    expect(Bookmark.where(user: user, lecture: lecture).count).to eq(1)
  end

  it 'ありがとうの連打は1件だけ作り、残りは500ではなく422にすること' do
    review = create(:review, lecture: lecture)

    statuses = concurrent_posts("/api/v1/reviews/#{review.id}/thanks",
                                bodies: Array.new(concurrency) { {} }, token: token)

    expect(statuses).to eq(201 => 1, 422 => concurrency - 1)
    expect(review.reload.thanks_count).to eq(1)
  end
end
