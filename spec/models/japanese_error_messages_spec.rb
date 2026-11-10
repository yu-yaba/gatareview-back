# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '利用者に返す検証エラーの文言' do
  # 数字・記号以外の英字が混ざっていたら、英語や翻訳漏れの文言が画面に出ている。
  def expect_japanese(messages)
    expect(messages).not_to be_empty
    messages.each { |message| expect(message).not_to match(/[A-Za-z]/), "英字を含む文言: #{message}" }
  end

  def flatten_keys(hash, prefix = nil)
    hash.flat_map do |key, value|
      path = [prefix, key].compact.join('.')
      value.is_a?(Hash) ? flatten_keys(value, path) : [path]
    end
  end

  it '既定のロケールが日本語であること' do
    expect(I18n.default_locale).to eq(:ja)
    expect(I18n.locale).to eq(:ja)
  end

  it 'Rails が英語で用意している検証エラーの文言をすべて日本語でも定義していること' do
    I18n.backend.send(:init_translations) unless I18n.backend.initialized?
    translations = I18n.backend.send(:translations)
    error_scopes = [%i[errors], %i[activerecord errors messages], %i[activemodel errors messages]]

    error_scopes.each do |scope|
      english = flatten_keys(translations[:en].dig(*scope) || {})
      japanese = flatten_keys(translations[:ja].dig(*scope) || {})
      # 英語の単数・複数形（one/other）は日本語では1つの文言にまとめる
      expected = english.map { |key| key.sub(/\.(one|other)\z/, '') }.uniq

      expect(expected - japanese).to eq([]), "#{scope.join('.')} に日本語の文言がないキー"
    end
  end

  it 'レビューの入力エラーを項目名つきの自然な日本語で返すこと' do
    review = Review.new(
      lecture: build(:lecture), rating: 5.5, content: 'あ' * 29, textbook: '未定義', attendance: '未定義',
      grading_type: '未定義', content_difficulty: '未定義', content_quality: '未定義', period_year: 'あ' * 256
    )

    expect(review).not_to be_valid
    expect_japanese(review.errors.full_messages)
    expect(review.errors.full_messages).to include(
      '総合評価は5以下の値にしてください', 'コメントは30文字以上で入力してください', '教科書は選択肢から選んでください',
      '出席確認は選択肢から選んでください', '採点方法は選択肢から選んでください', '単位取得難易度は選択肢から選んでください',
      '内容充実度は選択肢から選んでください', '授業を受けた年は255文字以内で入力してください'
    )
  end

  it 'レビューの未入力・数値以外・刻み違い・長すぎるコメントも日本語で返すこと' do
    blank = Review.new(rating: nil, content: '')
    expect(blank).not_to be_valid
    expect_japanese(blank.errors.full_messages)
    expect(blank.errors.full_messages).to include('総合評価を入力してください', 'コメントを入力してください',
                                                  '授業を指定してください')

    [[{ rating: 'abc' }, '総合評価は数値で入力してください'], [{ rating: 0 }, '総合評価は0.5以上の値にしてください'],
     [{ rating: 3.3 }, '総合評価は0.5刻みで入力してください'],
     [{ content: 'あ' * 1001 }, 'コメントは1000文字以内で入力してください']].each do |attributes, message|
      review = build(:review, **attributes)
      expect(review).not_to be_valid
      expect(review.errors.full_messages).to eq([message])
    end
  end

  it '同じ授業への2件目のレビューを項目名なしの文言で返すこと' do
    user = create(:user)
    existing = create(:review, user: user)
    duplicate = build(:review, user: user, lecture: existing.lecture)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.full_messages).to eq(['この授業にはすでにレビューを投稿しています'])
  end

  it 'ブックマーク・ありがとうの重複や自分のレビューへのありがとうを日本語で返すこと' do
    user = create(:user)
    lecture = create(:lecture)
    review = create(:review, lecture: lecture)
    Bookmark.create!(user: user, lecture: lecture)
    Thank.create!(user: user, review: review)

    bookmark = Bookmark.new(user: user, lecture: lecture)
    thank = Thank.new(user: user, review: review)
    own_thank = Thank.new(user: user, review: create(:review, user: user))

    expect([bookmark, thank, own_thank].map(&:valid?)).to all(be(false))
    expect(bookmark.errors.full_messages).to eq(['この授業はすでにブックマークしています'])
    expect(thank.errors.full_messages).to eq(['このレビューにはすでにありがとうを送っています'])
    expect(own_thank.errors.full_messages).to eq(['自分のレビューにはありがとうできません'])
    expect_japanese(Bookmark.new.tap(&:valid?).errors.full_messages + Thank.new.tap(&:valid?).errors.full_messages)
  end

  it '授業・ユーザー・サイト設定の入力エラーも日本語で返すこと' do
    existing = create(:lecture)
    blank_lecture = Lecture.new(title: ' ', lecturer: '', faculty: nil)
    duplicate_lecture = Lecture.new(title: existing.title, lecturer: existing.lecturer, faculty: existing.faculty)
    user = User.new
    setting = SiteSetting.new(id: 2, lecture_review_restriction_enabled: nil)

    [blank_lecture, duplicate_lecture, user, setting].each do |record|
      expect(record).not_to be_valid
      expect_japanese(record.errors.full_messages)
    end
    expect(duplicate_lecture.errors.full_messages).to eq(['授業名・教授/講師名・学部が同じ授業はすでに登録されています'])
  end

  it '例外の文言も日本語で組み立てること' do
    expect { Review.create!(rating: nil) }.to raise_error(ActiveRecord::RecordInvalid, /\A入力内容に誤りがあります: /)
  end
end
