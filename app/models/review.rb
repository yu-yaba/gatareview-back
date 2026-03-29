# frozen_string_literal: true

class Review < ApplicationRecord
  belongs_to :lecture
  belongs_to :user, optional: true, counter_cache: true
  has_many :thanks, dependent: :destroy

  validates :rating, presence: true
  validates :content, presence: true, length: { maximum: 1000 }

  validates :user_id, uniqueness: { scope: :lecture_id, allow_nil: true, message: 'は同じ講義に複数のレビューを投稿できません' }
end
