class User < ApplicationRecord
  has_many :reviews, dependent: :destroy
  has_many :thanks, dependent: :destroy
  has_many :bookmarks, dependent: :destroy

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
      id: id,
      email: email,
      name: name,
      avatar_url: avatar_url
    }
  end

  # アバター画像のURLを取得（デフォルト画像対応）
  def avatar_image_url
    avatar_url.present? ? avatar_url : nil
  end
end