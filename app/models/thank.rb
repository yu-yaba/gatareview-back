# frozen_string_literal: true

class Thank < ApplicationRecord
  belongs_to :user
  belongs_to :review, counter_cache: :thanks_count

  # DB の一意インデックス（user_id, review_id）でも保証する。
  validate :not_already_thanked, if: -> { new_record? || will_save_change_to_user_id? || will_save_change_to_review_id? }

  # 自分のレビューにはありがとうできないバリデーション
  validate :cannot_thank_own_review

  private

  def not_already_thanked
    return if user_id.nil? || review_id.nil?

    others = Thank.where(user_id: user_id, review_id: review_id)
    others = others.where.not(id: id) if persisted?
    errors.add(:base, :already_thanked) if others.exists?
  end

  def cannot_thank_own_review
    return unless user_id && review&.user_id

    errors.add(:base, :own_review) if user_id == review.user_id
  end
end
