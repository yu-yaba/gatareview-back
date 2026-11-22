# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261122000000_change_reviews_lecture_id_to_bigint.rb')

# 本番の変換前の状態（lecture_id が文字列で外部キーなし）を再現して確かめる。
# 列の変更は暗黙にコミットされるため、テストのトランザクションを使わずに元へ戻す。
RSpec.describe ChangeReviewsLectureIdToBigint do
  self.use_transactional_tests = false

  let(:connection) { ActiveRecord::Base.lease_connection }
  let(:lecture) { create(:lecture) }

  around do |example|
    ActiveRecord::Migration.suppress_messages do
      described_class.new.migrate(:down)
      Review.reset_column_information
      example.run
    ensure
      [Thank, Bookmark, Review, Lecture, User].each(&:delete_all)
      described_class.new.migrate(:up) unless connection.foreign_key_exists?(:reviews, :lectures, column: :lecture_id)
      Review.reset_column_information
    end
  end

  def lecture_id_type
    connection.columns(:reviews).find { |column| column.name == 'lecture_id' }.sql_type
  end

  def insert_review(lecture_id)
    connection.execute(<<~SQL.squish)
      INSERT INTO reviews (rating, content, lecture_id, created_at, updated_at)
      VALUES (4, '#{'あ' * 30}', #{connection.quote(lecture_id)}, NOW(), NOW())
    SQL
  end

  it '値を変えずに bigint へ変換し、存在しない授業を指すレビューは保存できなくすること' do
    insert_review(lecture.id.to_s)
    before = connection.select_rows('SELECT id, lecture_id FROM reviews ORDER BY id')

    described_class.new.migrate(:up)

    expect(lecture_id_type).to start_with('bigint')
    expect(connection.select_rows('SELECT id, lecture_id FROM reviews ORDER BY id'))
      .to eq(before.map { |id, lecture_id| [id, Integer(lecture_id)] })
    expect(connection.foreign_key_exists?(:reviews, :lectures, column: :lecture_id)).to be(true)
    expect { insert_review(lecture.id + 1000) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  context '本番と同じく、未使用列 lecture_id_bigint から lectures への外部キーが残っているとき' do
    around do |example|
      connection.add_column :reviews, :lecture_id_bigint, :bigint
      connection.add_foreign_key :reviews, :lectures, column: :lecture_id_bigint
      example.run
    ensure
      connection.remove_foreign_key :reviews, :lectures, column: :lecture_id_bigint, if_exists: true
      connection.remove_column :reviews, :lecture_id_bigint, if_exists: true
      Review.reset_column_information
    end

    it 'lecture_id の外部キーを追加し、down ではそれだけを外すこと' do
      described_class.new.migrate(:up)
      expect(connection.foreign_key_exists?(:reviews, :lectures, column: :lecture_id)).to be(true)

      described_class.new.migrate(:down)
      expect(connection.foreign_key_exists?(:reviews, :lectures, column: :lecture_id)).to be(false)
      expect(connection.foreign_key_exists?(:reviews, :lectures, column: :lecture_id_bigint)).to be(true)
    end
  end

  it 'down で文字列に戻し、外部キーを外すこと' do
    described_class.new.migrate(:up)
    described_class.new.migrate(:down)

    expect(lecture_id_type).to start_with('varchar')
    expect(connection.foreign_key_exists?(:reviews, :lectures, column: :lecture_id)).to be(false)
  end

  [
    ['数字でない値', ->(_lecture) { 'abc' }],
    ['先頭がゼロの値', ->(lecture) { "0#{lecture.id}" }],
    ['末尾に改行がある値', ->(lecture) { "#{lecture.id}\n" }],
    ['存在しない授業', ->(lecture) { (lecture.id + 1000).to_s }]
  ].each do |label, value|
    it "#{label}があれば一覧を示して中断し、データを変更しないこと" do
      bad_value = value.call(lecture)
      insert_review(bad_value)
      before = connection.select_rows('SELECT id, lecture_id FROM reviews ORDER BY id')

      expect { described_class.new.migrate(:up) }.to raise_error(ActiveRecord::MigrationError) do |error|
        expect(error.message).to include('データは変更していません', "lecture_id=#{bad_value.inspect}")
      end

      expect(connection.select_rows('SELECT id, lecture_id FROM reviews ORDER BY id')).to eq(before)
      expect(lecture_id_type).to start_with('varchar')
      expect(connection.foreign_key_exists?(:reviews, :lectures, column: :lecture_id)).to be(false)
    end
  end
end
