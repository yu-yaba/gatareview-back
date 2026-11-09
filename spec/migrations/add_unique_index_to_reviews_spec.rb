# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require Rails.root.join('db/migrate/20261109000000_add_unique_index_to_reviews_on_user_id_and_lecture_id.rb')

# 本番に一意インデックスを追加する前の状態（重複がありうる DB）を再現する。
# インデックスの削除・追加は暗黙にコミットされるため、テストのトランザクションを使わずに元へ戻す。
RSpec.describe AddUniqueIndexToReviewsOnUserIdAndLectureId do
  self.use_transactional_tests = false

  let(:index_name) { described_class::INDEX_NAME }
  let(:connection) { ActiveRecord::Base.lease_connection }
  let(:user) { create(:user) }
  let(:lecture) { create(:lecture) }

  around do |example|
    ActiveRecord::Migration.suppress_messages do
      connection.remove_index(:reviews, name: index_name) if connection.index_name_exists?(:reviews, index_name)
      example.run
    ensure
      [Thank, Bookmark, Review, Lecture, User].each(&:delete_all)
      connection.add_index(:reviews, %i[user_id lecture_id], unique: true, name: index_name) unless
        connection.index_name_exists?(:reviews, index_name)
    end
  end

  def unique_index?
    connection.indexes(:reviews).any? { |index| index.name == index_name && index.unique }
  end

  def create_duplicate_reviews
    first = create(:review, user: user, lecture: lecture, content: 'あ' * 30)
    second = build(:review, user: user, lecture: lecture, content: 'い' * 30)
    second.save!(validate: false)
    [first, second]
  end

  it '重複があれば一覧と確認方法を示して中断し、データを変更しないこと' do
    duplicates = create_duplicate_reviews
    before = Review.order(:id).pluck(:id, :user_id, :lecture_id, :content)

    expect { described_class.new.migrate(:up) }.to raise_error(ActiveRecord::MigrationError) do |error|
      expect(error.message).to include('1 組', 'bin/rails reviews:duplicates', 'docs/review-uniqueness-migration.md',
                                       "user_id=#{user.id} lecture_id=#{lecture.id} 件数=2 " \
                                       "review_ids=#{duplicates.map(&:id).join(',')}")
    end

    expect(Review.order(:id).pluck(:id, :user_id, :lecture_id, :content)).to eq(before)
    expect(unique_index?).to be(false)
  end

  it '重複がなければ一意インデックスを追加し、匿名レビューは同じ授業に複数保存できること' do
    create(:review, user: user, lecture: lecture)
    2.times { create(:review, user: nil, lecture: lecture) }

    described_class.new.migrate(:up)

    expect(unique_index?).to be(true)
    expect { build(:review, user: nil, lecture: lecture).save!(validate: false) }.to change(Review, :count).by(1)
    expect { build(:review, user: user, lecture: lecture).save!(validate: false) }
      .to raise_error(ActiveRecord::RecordNotUnique)

    described_class.new.migrate(:down)
    expect(unique_index?).to be(false)
  end

  describe '重複が残っている間の本人による編集', type: :request do
    it 'どちらのレビューも編集できること' do
      duplicates = create_duplicate_reviews
      headers = { 'Authorization' => "Bearer #{JsonWebToken.encode(user.jwt_payload)}" }

      duplicates.each do |review|
        patch "/api/v1/reviews/#{review.id}", params: { review: { rating: 2 } }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(review.reload.rating).to eq(2.0)
      end
    end
  end

  describe 'reviews:duplicates' do
    let(:task) { Rake.application['reviews:duplicates'] }

    around do |example|
      original_application = Rake.application
      Rake.application = Rake::Application.new
      Rake::Task.define_task(:environment)
      load Rails.root.join('lib/tasks/reviews.rake').to_s
      example.run
    ensure
      Rake.application = original_application
    end

    it '重複の組とレビューを本文なしで表示し、終了コード1で終わること' do
      duplicates = create_duplicate_reviews

      expect do
        expect { task.invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(
        a_string_including("user_id=#{user.id} lecture_id=#{lecture.id} 件数=2", "id=#{duplicates.first.id} ",
                           "id=#{duplicates.last.id} ", '本文=30文字')
          .and(satisfy { |text| !text.include?('あ' * 30) && !text.include?('い' * 30) })
      ).to_stdout
      expect(Review.count).to eq(2)
    end

    it '重複がなければその旨を表示すること' do
      create(:review, user: user, lecture: lecture)

      expect { task.invoke }.to output(/重複はありません/).to_stdout
    end
  end
end
