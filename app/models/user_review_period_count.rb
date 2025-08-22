# frozen_string_literal: true

class UserReviewPeriodCount < ApplicationRecord
  belongs_to :user
  belongs_to :review_period

  validates :reviews_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :user_id, uniqueness: { scope: :review_period_id }

  scope :for_period, ->(period) { where(review_period: period) }
  scope :for_user, ->(user) { where(user: user) }

  def increment!
    increment(:reviews_count)
    save!
  end

  def decrement!
    return if reviews_count <= 0
    
    decrement(:reviews_count)
    save!
  end
end