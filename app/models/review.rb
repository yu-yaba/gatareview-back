# frozen_string_literal: true

class Review < ApplicationRecord
  belongs_to :lecture
  belongs_to :user, optional: true
  has_many :thanks, dependent: :destroy

  validates :rating, presence: true
  validates :content, presence: true, length: { minimum: 20, maximum: 400, too_short: "は%{count}文字以上で入力してください" }

  validates :user_id, uniqueness: { scope: :lecture_id, allow_nil: true, message: 'は同じ講義に複数のレビューを投稿できません' }

  after_create :increment_user_reviews_count
  after_destroy :decrement_user_reviews_count

  private

  def increment_user_reviews_count
    user&.increment!(:reviews_count)
  end

  def decrement_user_reviews_count
    user&.decrement!(:reviews_count)
  end
end
