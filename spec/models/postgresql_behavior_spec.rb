# frozen_string_literal: true

require 'rails_helper'

# MySQL（utf8mb4_0900_ai_ci）から PostgreSQL に移したときに変わりうる挙動を固定する。
RSpec.describe 'PostgreSQL での比較と制約違反' do
  describe '授業の検索（照合順序 ci_ai）' do
    let!(:lecture) { create(:lecture, title: 'バス演習Ａ', lecturer: '山田 太郎') }

    {
      'ひらがな' => 'ばす',
      '濁点なし' => 'はす',
      '半角カナ' => 'ﾊﾞｽ',
      '全角英字を半角・小文字で' => '演習a',
      '全角スペースの教員名' => '山田　太郎'
    }.each do |label, keyword|
      it "#{label}（#{keyword}）でもヒットすること" do
        expect(Lecture.search_by_title_and_lecturer(keyword)).to contain_exactly(lecture)
      end
    end

    it 'LIKE の記号は文字としてそのまま比べること' do
      create(:lecture, title: '50%割引演習')

      expect(Lecture.search_by_title_and_lecturer('50%').pluck(:title)).to eq(['50%割引演習'])
      expect(Lecture.search_by_title_and_lecturer('_')).to be_empty
    end
  end

  describe '授業の重複（title, lecturer, faculty）' do
    it '大文字小文字・全角半角・かなの違いだけの授業は重複として弾くこと' do
      create(:lecture, title: '英語Ａ', lecturer: 'ヤマダ', faculty: '教育学部')
      duplicate = build(:lecture, title: '英語a', lecturer: 'やまだ', faculty: '教育学部')

      expect(duplicate).not_to be_valid
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it '漢字が違う授業は別の授業として保存できること' do
      create(:lecture, title: '数学', lecturer: '高橋', faculty: '理学部')

      expect(create(:lecture, title: '数学', lecturer: '髙橋', faculty: '理学部')).to be_persisted
    end
  end

  describe 'User.from_google_oauth' do
    before { create(:user, email: 'Student@Example.com', provider: 'google', provider_id: 'existing-sub') }

    let(:identity) { { 'sub' => 'another-sub', 'email' => 'student@example.com', 'name' => 'Another' } }

    it 'メールアドレスの大文字小文字だけが違う別アカウントは、検証で重複として弾くこと' do
      expect { User.from_google_oauth(identity) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it '検証をすり抜けた同時作成でも、トランザクションを壊さずに読み直して RecordNotFound で止まること' do
      allow(User).to receive(:create!).and_wrap_original do |_original, attributes|
        User.new(attributes).tap { |user| user.save!(validate: false) }
      end

      expect { User.from_google_oauth(identity) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(User.count).to eq(1)
    end
  end
end
