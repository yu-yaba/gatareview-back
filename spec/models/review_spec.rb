# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Review, type: :model do
  describe 'content validation' do
    [30, 1000].each do |length|
      it "#{length}文字の本文を受理すること" do
        expect(FactoryBot.build(:review, content: 'あ' * length)).to be_valid
      end
    end

    [0, 29, 1001].each do |length|
      it "#{length}文字の本文を拒否すること" do
        review = FactoryBot.build(:review, content: 'あ' * length)
        expect(review).not_to be_valid
        expect(review.errors[:content]).to be_present
      end
    end
  end

  describe 'rating validation' do
    [0.5, 1, 3.5, 5, 5.0].each do |rating|
      it "#{rating}の0.5刻みの評価を受理すること" do
        expect(FactoryBot.build(:review, rating: rating)).to be_valid
      end
    end

    [nil, 0, 0.1, 5.5, 999, -1, 3.3, '5invalid', 'NaN', 'Infinity'].each do |rating|
      it "不正な評価#{rating.inspect}を拒否すること" do
        review = FactoryBot.build(:review, rating: rating)
        expect(review).not_to be_valid
        expect(review.errors[:rating]).to be_present
      end
    end
  end

  describe 'detail choices and legacy compatibility' do
    {
      textbook: %w[必要 不要 どちらでも その他・不明],
      attendance: %w[毎回確認 たまに確認 なし その他・不明],
      grading_type: %w[テストのみ レポートのみ テスト,レポート その他・不明],
      content_difficulty: %w[とても楽 楽 普通 難 とても難しい],
      content_quality: %w[とても良い 良い 普通 悪い とても悪い]
    }.each do |attribute, choices|
      it "#{attribute}の画面上の選択肢と任意の空欄を受理すること" do
        [*choices, '', nil].each do |choice|
          expect(FactoryBot.build(:review, attribute => choice)).to be_valid
        end
      end

      it "#{attribute}の未定義の選択肢を拒否すること" do
        review = FactoryBot.build(:review, attribute => '未定義の入力')
        expect(review).not_to be_valid
        expect(review.errors[attribute]).to be_present
      end
    end

    it '変更していない旧データを保持して本文だけを更新できること' do
      review = FactoryBot.create(:review)
      review.update_columns(rating: 3.3, content: '旧データの短い本文', textbook: '旧教科書選択肢')

      expect(review.reload.update(content: 'あ' * 30)).to be(true)
      expect(review.reload).to have_attributes(rating: 3.3, textbook: '旧教科書選択肢', content: 'あ' * 30)
    end

    it '旧データでも変更する属性には現在の入力制約を適用すること' do
      review = FactoryBot.create(:review)
      review.update_columns(rating: 3.3, content: '旧データの短い本文', textbook: '旧教科書選択肢')

      expect(review.reload.update(rating: 4.4, content: '別の短文', textbook: '別の未定義値')).to be(false)
      expect(review.errors.attribute_names).to include(:rating, :content, :textbook)
      expect(review.reload).to have_attributes(rating: 3.3, content: '旧データの短い本文', textbook: '旧教科書選択肢')
    end
  end

  describe 'syllabus references' do
    let(:lecture) { FactoryBot.create(:lecture) }
    let!(:offering) do
      LectureOffering.create!(
        lecture: lecture,
        year: 2026,
        registration_code: '261H2001',
        shozoku_code: '01',
        term_code: 'A'
      )
    end

    it 'writes the additive lecture reference and assigns a unique offering' do
      review = FactoryBot.build(
        :review,
        lecture: lecture,
        period_year: '2025',
        period_term: '3ターム',
        academic_year: 2026,
        term_code: 'A'
      )

      expect(review).to be_valid
      expect(review.lecture_id_bigint).to eq(lecture.id)
      expect(review.lecture_offering).to eq(offering)
      expect(review).to have_attributes(academic_year: 2026, term_code: 'A')
    end

    it 'legacy period fieldsの変更時に正規化値を再計算し不明値をnilにする' do
      review = FactoryBot.create(
        :review,
        lecture: lecture,
        lecture_offering: offering,
        period_year: '2026',
        period_term: '1ターム',
        academic_year: 2026,
        term_code: 'A'
      )

      review.update!(period_year: '2025', period_term: '3ターム', lecture_offering_id: nil)
      expect(review).to have_attributes(academic_year: 2025, term_code: 'C', lecture_offering_id: nil)

      review.update!(period_year: 'その他', period_term: '不明')
      expect(review).to have_attributes(academic_year: nil, term_code: nil, lecture_offering_id: nil)
    end

    it '同年度のOfferingが1件でも明示的な関連解除を打ち消さない' do
      review = FactoryBot.create(
        :review,
        lecture: lecture,
        lecture_offering: offering,
        period_year: '2026',
        period_term: '1ターム',
        academic_year: 2026,
        term_code: 'A'
      )

      review.update!(period_term: 'その他・不明', lecture_offering_id: nil)

      expect(review).to have_attributes(
        academic_year: 2026,
        term_code: nil,
        lecture_offering_id: nil
      )
    end

    it '明示したOfferingから変換表外の年度・タームを補完する' do
      semester_offering = LectureOffering.create!(
        lecture: FactoryBot.create(:lecture, title: '第1学期講義'),
        year: 2026,
        registration_code: '261H2002',
        shozoku_code: '01',
        term_code: '1'
      )
      review = FactoryBot.build(
        :review,
        lecture: semester_offering.lecture,
        lecture_offering: semester_offering,
        period_year: '不明',
        period_term: '不明',
        academic_year: nil,
        term_code: nil
      )

      expect(review).to be_valid
      expect(review).to have_attributes(academic_year: 2026, term_code: '1')
    end

    it 'シラバスの全開講区分をレビュー用表記から正規化できる' do
      expected_codes = {
        '第1学期' => '1', '第2学期' => '2', '通年' => '3', '集中' => '4',
        '年度跨り' => '5', '時間外' => '9', '1ターム' => 'A', '2ターム' => 'B',
        '3ターム' => 'C', '4ターム' => 'D', '1, 2ターム' => 'E',
        '3, 4ターム' => 'F', '2, 3ターム' => 'G', '1～3ターム' => 'H',
        '2～4ターム' => 'I'
      }

      expected_codes.each do |period_term, term_code|
        review = FactoryBot.build(
          :review,
          lecture: lecture,
          period_year: '2026',
          period_term: period_term,
          academic_year: nil,
          term_code: nil,
          lecture_offering: nil
        )

        review.valid?
        expect(review.term_code).to eq(term_code)
      end
    end

    it '自動関連付けしたOfferingから複合タームコードを補完する' do
      composite_lecture = FactoryBot.create(:lecture, title: '第2,3ターム講義')
      composite_offering = LectureOffering.create!(
        lecture: composite_lecture,
        year: 2026,
        registration_code: '261H2003',
        shozoku_code: '01',
        term_code: 'G'
      )
      review = FactoryBot.build(
        :review,
        lecture: composite_lecture,
        period_year: '2026',
        period_term: '2,3ターム',
        academic_year: nil,
        term_code: nil
      )

      expect(review).to be_valid
      expect(review).to have_attributes(
        lecture_offering: composite_offering,
        academic_year: 2026,
        term_code: 'G'
      )
    end

    it '年度・ターム変更時に既存関連を外し、変更先の一意なOfferingへ付け替える' do
      second_offering = LectureOffering.create!(
        lecture: lecture,
        year: 2026,
        registration_code: '261H2004',
        shozoku_code: '01',
        term_code: 'B'
      )
      review = FactoryBot.create(
        :review,
        lecture: lecture,
        lecture_offering: offering,
        academic_year: 2026,
        term_code: 'A'
      )

      review.update!(academic_year: 2026, term_code: 'B')

      expect(review.reload.lecture_offering).to eq(second_offering)
    end

    it 'rejects an offering whose term does not match the review' do
      review = FactoryBot.build(
        :review,
        lecture: lecture,
        lecture_offering: offering,
        academic_year: 2026,
        term_code: 'B'
      )

      expect(review).not_to be_valid
      expect(review.term_code).to eq('B')
      expect(review.errors[:lecture_offering]).to include('は受講タームと一致しません')
    end

    it '保存直前にOfferingを再取得し、古いactive状態では関連付けない' do
      review = FactoryBot.build(
        :review,
        lecture: lecture,
        lecture_offering: offering,
        academic_year: 2026,
        term_code: 'A'
      )
      LectureOffering.where(id: offering.id).update_all(source_status: 'missing')

      expect(review).not_to be_valid
      expect(review.errors[:lecture_offering]).to include('は現在有効ではありません')
    end

    it '保存直前に削除されたOfferingを古いassociation cacheから関連付けない' do
      review = FactoryBot.build(
        :review,
        lecture: lecture,
        lecture_offering: offering,
        academic_year: 2026,
        term_code: 'A'
      )
      LectureOffering.where(id: offering.id).delete_all

      expect(review).not_to be_valid
      expect(review.errors[:lecture_offering]).to include('が見つかりません')
    end
  end
end
