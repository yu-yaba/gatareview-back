# frozen_string_literal: true

class TimetableEntry < ApplicationRecord
  belongs_to :user
  belongs_to :lecture

  validates :year, :term, presence: true
  validates :term, inclusion: { in: 0..4 }
  validates :day, :period, presence: true, unless: :intensive?
  validates :day, inclusion: { in: 1..7 }, allow_nil: true
  validates :period, inclusion: { in: 1..7 }, allow_nil: true
  validates :user_id, uniqueness: { scope: %i[year term day period], message: 'このコマには既に講義が登録されています' }, unless: :intensive?
  validates :lecture_id, uniqueness: { scope: %i[user_id year term], message: 'この講義は既に登録されています' }, if: :intensive?

  def intensive?
    term == 0
  end
end
