# frozen_string_literal: true

class Thank < ApplicationRecord
  belongs_to :user
  belongs_to :review, counter_cache: :thanks_count

  validates :user_id, uniqueness: { scope: :review_id, message: 'このレビューには既にありがとうを送信済みです' }
  
  # 自分のレビューにはありがとうできないバリデーション
  validate :cannot_thank_own_review

  private

  def cannot_thank_own_review
    return unless user_id && review&.user_id
    
    errors.add(:base, '自分のレビューにはありがとうできません') if user_id == review.user_id
  end
end