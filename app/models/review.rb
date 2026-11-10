# frozen_string_literal: true

class Review < ApplicationRecord
  # Preserve these database columns without exposing the removed feature in the API.
  self.ignored_columns += %w[lecture_id_bigint lecture_offering_id academic_year term_code]

  DETAIL_OPTIONS = {
    textbook: %w[必要 不要 どちらでも その他・不明],
    attendance: %w[毎回確認 たまに確認 なし その他・不明],
    grading_type: %w[テストのみ レポートのみ テスト,レポート その他・不明],
    content_difficulty: %w[とても楽 楽 普通 難 とても難しい],
    content_quality: %w[とても良い 良い 普通 悪い とても悪い]
  }.freeze

  belongs_to :lecture
  belongs_to :user, optional: true, counter_cache: true
  has_many :thanks, dependent: :destroy

  validates :rating, presence: true, numericality: true
  validates :rating, numericality: { greater_than_or_equal_to: 0.5, less_than_or_equal_to: 5 },
                     if: -> { new_record? || will_save_change_to_rating? }
  validate :rating_uses_half_star_steps, if: -> { new_record? || will_save_change_to_rating? }
  validates :content, presence: true
  validates :content, length: { in: 30..1000 }, if: -> { new_record? || will_save_change_to_content? }

  # Preserve untouched legacy values while enforcing the current form choices on new input.
  DETAIL_OPTIONS.each do |attribute, values|
    validates attribute, inclusion: { in: values }, allow_blank: true,
                         if: -> { new_record? || will_save_change_to_attribute?(attribute) }
  end

  %i[period_year period_term].each do |attribute|
    validates attribute, length: { maximum: 255 }, allow_nil: true,
                         if: -> { new_record? || will_save_change_to_attribute?(attribute) }
  end

  # ログイン利用者は1つの授業にレビューを1件だけ投稿できる（DB の一意インデックスでも保証する）。
  # 投稿者や授業が変わるときだけ確認するので、過去にできた重複があっても本人は各レビューを編集できる。
  validate :one_review_per_user_and_lecture,
           if: -> { user_id.present? && (new_record? || will_save_change_to_user_id? || will_save_change_to_lecture_id?) }

  # 同じ内容の再送かどうかを比べる、投稿フォームから受け取る項目。
  SUBMITTED_ATTRIBUTES = %w[
    rating content textbook attendance grading_type content_difficulty content_quality period_year period_term
  ].freeze

  def same_submission_as?(other)
    SUBMITTED_ATTRIBUTES.all? { |name| self[name] == other[name] }
  end

  private

  def one_review_per_user_and_lecture
    others = Review.where(user_id: user_id, lecture_id: lecture_id)
    others = others.where.not(id: id) if persisted?
    errors.add(:base, :already_reviewed) if others.exists?
  end

  def rating_uses_half_star_steps
    return unless rating&.finite? && rating.between?(0.5, 5)
    return if rating * 2 == (rating * 2).to_i

    errors.add(:rating, 'は0.5刻みで入力してください')
  end
end
