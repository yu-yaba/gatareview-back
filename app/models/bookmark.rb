# frozen_string_literal: true

class Bookmark < ApplicationRecord
  belongs_to :user
  belongs_to :lecture

  validates :user_id, uniqueness: { scope: :lecture_id, message: 'この授業は既にブックマーク済みです' }
end