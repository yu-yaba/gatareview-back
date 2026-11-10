# frozen_string_literal: true

class Bookmark < ApplicationRecord
  belongs_to :user
  belongs_to :lecture

  # DB の一意インデックス（user_id, lecture_id）でも保証する。
  validate :not_already_bookmarked, if: -> { new_record? || will_save_change_to_user_id? || will_save_change_to_lecture_id? }

  private

  def not_already_bookmarked
    return if user_id.nil? || lecture_id.nil?

    others = Bookmark.where(user_id: user_id, lecture_id: lecture_id)
    others = others.where.not(id: id) if persisted?
    errors.add(:base, :already_bookmarked) if others.exists?
  end
end
