# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Existing API with unused syllabus columns', type: :model do
  before do
    connection = ActiveRecord::Base.connection
    connection.create_table :unused_syllabus_lectures, temporary: true do |table|
      table.string :title
      table.string :lecturer
      table.string :faculty
      table.string :normalized_key, default: 'preserved-key'
      table.bigint :merged_into_lecture_id, default: 123
      table.datetime :merged_at
      table.timestamps
    end
    connection.create_table :unused_syllabus_reviews, temporary: true do |table|
      table.string :lecture_id
      table.bigint :user_id
      table.float :rating
      table.text :content
      table.string :period_year
      table.string :period_term
      table.integer :thanks_count, default: 0
      %i[textbook attendance grading_type content_difficulty content_quality].each do |attribute|
        table.string attribute
      end
      table.bigint :lecture_id_bigint, default: 456
      table.bigint :lecture_offering_id, default: 789
      table.integer :academic_year, default: 2026
      table.string :term_code, default: 'A'
      table.timestamps
    end

    stub_const('UnusedSyllabusLecture', Class.new(Lecture))
    stub_const('UnusedSyllabusReview', Class.new(Review))
    UnusedSyllabusLecture.table_name = 'unused_syllabus_lectures'
    UnusedSyllabusReview.table_name = 'unused_syllabus_reviews'
    UnusedSyllabusLecture.has_many :reviews, class_name: 'UnusedSyllabusReview', foreign_key: :lecture_id
    UnusedSyllabusReview.belongs_to :lecture, class_name: 'UnusedSyllabusLecture'
  end

  after do
    connection = ActiveRecord::Base.connection
    connection.execute('DROP TEMPORARY TABLE IF EXISTS unused_syllabus_reviews')
    connection.execute('DROP TEMPORARY TABLE IF EXISTS unused_syllabus_lectures')
  end

  let(:lecture) do
    UnusedSyllabusLecture.create!(title: '既存授業', lecturer: '既存教員', faculty: 'E:経済科学部')
  end
  let!(:review) do
    UnusedSyllabusReview.create!(
      lecture: lecture, rating: 4, content: 'あ' * 30,
      period_year: '2023', period_term: '春'
    )
  end

  it 'returns the existing lecture and review fields without the unused database columns' do
    lecture_json = lecture.reload.as_json_with_reviews
    review_json = review.reload.as_json

    expect(lecture_json).to include('title' => '既存授業', avg_rating: 4.0, review_count: 1)
    expect(lecture_json.keys.map(&:to_s)).not_to include('normalized_key', 'merged_into_lecture_id', 'merged_at', 'offering')
    expect(review_json).to include('period_year' => '2023', 'period_term' => '春', 'rating' => 4.0)
    expect(review_json.keys).not_to include('lecture_id_bigint', 'lecture_offering_id', 'academic_year', 'term_code')
  end

  it 'updates existing content while preserving the unused column values' do
    lecture.update!(title: '更新後の授業')
    review.update!(rating: 4.5, content: 'い' * 30, period_year: '', period_term: 'その他・不明')

    connection = ActiveRecord::Base.connection
    lecture_columns = connection.select_one(
      "SELECT normalized_key, merged_into_lecture_id FROM unused_syllabus_lectures WHERE id = #{lecture.id}"
    )
    review_columns = connection.select_one(
      'SELECT lecture_id_bigint, lecture_offering_id, academic_year, term_code ' \
      "FROM unused_syllabus_reviews WHERE id = #{review.id}"
    )
    expect(lecture_columns).to eq('normalized_key' => 'preserved-key', 'merged_into_lecture_id' => 123)
    expect(review_columns).to eq(
      'lecture_id_bigint' => 456, 'lecture_offering_id' => 789,
      'academic_year' => 2026, 'term_code' => 'A'
    )
    expect(review.reload).to have_attributes(
      rating: 4.5, content: 'い' * 30,
      period_year: '', period_term: 'その他・不明'
    )
  end
end
