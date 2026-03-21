class SiteSetting < ApplicationRecord
  SINGLETON_ID = 1

  belongs_to :last_updated_by, class_name: 'User', foreign_key: :last_updated_by_user_id,
                               optional: true, inverse_of: :updated_site_settings

  before_validation :assign_singleton_id, on: :create

  validates :lecture_review_restriction_enabled, inclusion: { in: [true, false] }
  validates :id, inclusion: { in: [SINGLETON_ID] }

  def self.current
    return new(id: SINGLETON_ID, lecture_review_restriction_enabled: false) unless table_ready?

    find_by(id: SINGLETON_ID) || new(id: SINGLETON_ID, lecture_review_restriction_enabled: false)
  end

  def self.current!
    raise ActiveRecord::StatementInvalid, 'site_settings table is missing' unless table_ready?

    find_or_create_by!(id: SINGLETON_ID) do |setting|
      setting.lecture_review_restriction_enabled = false
    end
  end

  def self.table_ready?
    connection.schema_cache.data_source_exists?(table_name)
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    false
  end

  private

  def assign_singleton_id
    self.id ||= SINGLETON_ID
  end
end
