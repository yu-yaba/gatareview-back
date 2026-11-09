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

  # 全スレッドが揃ってから一斉に送り、[HTTPメソッド, ステータス] ごとの件数を返す。例外はクラス名で数える。
  # requests: [[HTTPメソッド, パス, 本文, トークン], ...]
  def concurrent_requests(requests)
    gate = Queue.new
    threads = requests.map do |method, path, body, request_token|
      Thread.new do
        gate.pop
        env = { 'CONTENT_TYPE' => 'application/json', input: body.to_json }
        env['HTTP_AUTHORIZATION'] = "Bearer #{request_token}" if request_token
        [method, Rack::MockRequest.new(Rails.application).request(method, path, env).status]
      rescue StandardError => e
        [method, "#{e.class}: #{e.message.lines.first}"]
      end
    end
    requests.size.times { gate << true }
    threads.map(&:value).tally
  end

  def concurrent_posts(path, bodies:, token: nil)
    concurrent_requests(bodies.map { |body| ['POST', path, body, token] }).transform_keys(&:last)
  end

  def token_for(other_user)
    JsonWebToken.encode(other_user.jwt_payload)
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

  it '匿名の同時投稿は500にならずにすべて保存すること（匿名投稿は再送としてまとめない）' do
    statuses = concurrent_posts("/api/v1/lectures/#{lecture.id}/reviews",
                                bodies: Array.new(concurrency) { { review: review_attributes } })

    expect(statuses).to eq(201 => concurrency)
    expect(Review.where(lecture_id: lecture.id).count).to eq(concurrency)
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

  it '別々の利用者が同じレビューへ同時にありがとうしても、500にならず件数がずれないこと' do
    review = create(:review, lecture: lecture)
    tokens = Array.new(concurrency) { token_for(create(:user)) }

    3.times do
      Thank.where(review: review).delete_all
      Review.where(id: review.id).update_all(thanks_count: 0)

      statuses = concurrent_requests(tokens.map { |other| ['POST', "/api/v1/reviews/#{review.id}/thanks", {}, other] })

      expect(statuses).to eq(['POST', 201] => concurrency)
      expect(review.reload.thanks_count).to eq(Thank.where(review: review).count).and eq(concurrency)
    end
  end

  it 'ありがとうの送信と取り消しが同時に届いても、500にならず件数がずれないこと' do
    review = create(:review, lecture: lecture)
    senders = Array.new(concurrency / 2) { create(:user) }
    cancellers = Array.new(concurrency / 2) { create(:user) }

    3.times do
      Thank.where(review: review).delete_all
      cancellers.each { |canceller| Thank.create!(user: canceller, review: review) }
      Review.reset_counters(review.id, :thanks)

      requests = senders.map { |sender| ['POST', "/api/v1/reviews/#{review.id}/thanks", {}, token_for(sender)] } +
                 cancellers.map { |canceller| ['DELETE', "/api/v1/reviews/#{review.id}/thanks", {}, token_for(canceller)] }
      statuses = concurrent_requests(requests)

      expect(statuses).to eq(['POST', 201] => senders.size, ['DELETE', 200] => cancellers.size)
      expect(review.reload.thanks_count).to eq(Thank.where(review: review).count).and eq(senders.size)
    end
  end

  it '投稿者がレビューを削除する間にありがとうが届いても、500にならず関連も残さないこと' do
    thankers = Array.new(concurrency - 1) { create(:user) }

    5.times do
      review = create(:review, lecture: create(:lecture), user: user)
      requests = [['DELETE', "/api/v1/reviews/#{review.id}", {}, token]] +
                 thankers.map { |thanker| ['POST', "/api/v1/reviews/#{review.id}/thanks", {}, token_for(thanker)] }

      statuses = concurrent_requests(requests)

      expect(statuses).to include(['DELETE', 200] => 1)
      expect(statuses.keys - [['DELETE', 200], ['POST', 201], ['POST', 404]]).to eq([])
      expect(Review.exists?(review.id)).to be(false)
      expect(Thank.where(review_id: review.id).count).to eq(0)
    end
    expect(user.reload.reviews_count).to eq(0)
  end
end
