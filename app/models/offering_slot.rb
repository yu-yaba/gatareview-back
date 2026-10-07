# frozen_string_literal: true

# 開講の1コマ（曜日×時限）。「月2, 木2」は2レコードになる。
# 曜限のない開講（集中・「他」）にはレコードを作らない
class OfferingSlot < ApplicationRecord
  DAYS = { '月' => 1, '火' => 2, '水' => 3, '木' => 4, '金' => 5, '土' => 6, '日' => 7 }.freeze

  belongs_to :lecture_offering

  validates :day, presence: true, inclusion: { in: 1..7 }
  validates :period, presence: true, inclusion: { in: 1..7 }
  validates :day, uniqueness: { scope: %i[lecture_offering_id period] }
end
