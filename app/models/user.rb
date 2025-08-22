class User < ApplicationRecord
  has_many :reviews, dependent: :destroy
  has_many :thanks, dependent: :destroy
  has_many :bookmarks, dependent: :destroy
  has_many :user_review_period_counts, dependent: :destroy
  has_many :review_periods, through: :user_review_period_counts

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
  validates :provider, presence: true
  validates :provider_id, presence: true, uniqueness: { scope: :provider }

  # Google認証用のユーザー作成またはログイン
  def self.from_google_oauth(google_user_info)
    # トランザクションでデータ整合性を保証
    transaction do
      # 既存ユーザーをロックして競合状態を防ぐ
      user = where(provider: 'google', provider_id: google_user_info['sub']).lock.first

      if user
        # 既存ユーザーの情報更新（名前やアバターが変更されている可能性）
        user.update!(
          name: google_user_info['name'],
          avatar_url: google_user_info['picture']
        )
        user
      else
        # 新規ユーザー作成（Unique制約違反を適切にハンドリング）
        begin
          create!(
            email: google_user_info['email'],
            name: google_user_info['name'],
            provider: 'google',
            provider_id: google_user_info['sub'],
            avatar_url: google_user_info['picture']
          )
        rescue ActiveRecord::RecordNotUnique => e
          Rails.logger.warn "Duplicate user creation attempt: #{e.message}"
          # 競合が発生した場合は再度検索
          where(provider: 'google', provider_id: google_user_info['sub']).first!
        end
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "User creation/update failed: #{e.message}"
    raise e
  rescue => e
    Rails.logger.error "Unexpected error in from_google_oauth: #{e.message}"
    raise e
  end

  # JWT用のペイロード作成
  def jwt_payload
    {
      user_id: id,
      email: email,
      name: name,
      avatar_url: avatar_url
    }
  end

  # アバター画像のURLを取得（デフォルト画像対応）
  def avatar_image_url
    avatar_url.present? ? avatar_url : nil
  end

  # 現在の期間での投稿レビュー数を取得
  def reviews_count_for_period(period = nil)
    period ||= ReviewPeriod.current_period
    return 0 unless period
    
    user_review_period_counts.find_by(review_period: period)&.reviews_count || 0
  end

  # 現在の期間でレビューアクセス権限があるかチェック
  def has_review_access_for_period?(period = nil)
    reviews_count_for_period(period) >= 1
  end

  # レビュー投稿時に期間別カウントを増加
  def increment_period_review_count!(period = nil)
    period ||= ReviewPeriod.current_period
    return unless period
    
    count_record = user_review_period_counts.find_or_initialize_by(review_period: period)
    count_record.reviews_count = (count_record.reviews_count || 0) + 1
    count_record.save!
    
    # 全体のレビュー数も更新
    increment!(:reviews_count)
    
    count_record.reviews_count
  end

  # レビュー削除時に期間別カウントを減少
  def decrement_period_review_count!(period = nil)
    period ||= ReviewPeriod.current_period
    return unless period
    
    count_record = user_review_period_counts.find_by(review_period: period)
    return unless count_record && count_record.reviews_count > 0
    
    count_record.reviews_count -= 1
    count_record.save!
    
    # 全体のレビュー数も更新
    decrement!(:reviews_count) if reviews_count > 0
    
    count_record.reviews_count
  end
end