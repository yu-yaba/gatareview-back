# frozen_string_literal: true

class Review < ApplicationRecord
  belongs_to :lecture
  belongs_to :user, optional: true # 既存データとの互換性のため一時的にoptional
  has_many :thanks, dependent: :destroy

  validates :user_id, uniqueness: { scope: :lecture_id, allow_nil: true, message: 'は同じ講義に複数のレビューを投稿できません' }
end
