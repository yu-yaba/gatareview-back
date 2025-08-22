# frozen_string_literal: true

class ReviewPeriod < ApplicationRecord
  has_many :user_review_period_counts, dependent: :destroy
  has_many :users, through: :user_review_period_counts

  validates :period_name, presence: true, uniqueness: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :end_date_after_start_date
  validate :only_one_active_period

  scope :active, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }
  scope :current, -> { where('start_date <= ? AND end_date >= ?', Time.current, Time.current) }

  def self.current_period
    active.first
  end

  def activate!
    ActiveRecord::Base.transaction do
      # 現在のアクティブな期間を無効にする
      ReviewPeriod.where(is_active: true).update_all(is_active: false)
      # この期間をアクティブにする
      update!(is_active: true)
    end
  end

  def deactivate!
    update!(is_active: false)
  end

  def within_period?(datetime = Time.current)
    start_date <= datetime && datetime <= end_date
  end

  def user_reviews_count(user)
    user_review_period_counts.find_by(user: user)&.reviews_count || 0
  end

  def increment_user_reviews_count!(user)
    count_record = user_review_period_counts.find_or_initialize_by(user: user)
    count_record.reviews_count = (count_record.reviews_count || 0) + 1
    count_record.save!
    count_record.reviews_count
  end

  private

  def end_date_after_start_date
    return unless start_date && end_date
    
    if end_date <= start_date
      errors.add(:end_date, 'must be after start date')
    end
  end

  def only_one_active_period
    return unless is_active

    existing_active = ReviewPeriod.where(is_active: true)
    existing_active = existing_active.where.not(id: id) if persisted?
    
    if existing_active.exists?
      errors.add(:is_active, 'only one period can be active at a time')
    end
  end
end