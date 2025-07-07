class Api::V1::AuthController < ApplicationController
  include Authenticatable
  skip_before_action :authenticate_request, only: [:google_oauth]
  before_action :authenticate_optional, only: [:me]

  # Google OAuth認証
  def google_oauth
    begin
      # Googleトークンを検証
      google_user_info = verify_google_token(params[:token])
      
      if google_user_info
        # ユーザーを作成または取得
        user = User.from_google_oauth(google_user_info)
        
        if user.persisted?
          # JWTトークンを生成
          token = JsonWebToken.encode(user.jwt_payload)
          
          render json: {
            message: 'ログインに成功しました',
            token: token,
            user: {
              id: user.id,
              email: user.email,
              name: user.name,
              avatar_url: user.avatar_url
            }
          }, status: :ok
        else
          render json: { error: 'ユーザーの作成に失敗しました' }, status: :unprocessable_entity
        end
      else
        render json: { error: '無効なGoogleトークンです' }, status: :unauthorized
      end
    rescue => e
      Rails.logger.error "Google OAuth error: #{e.message}"
      render json: { error: '認証に失敗しました' }, status: :internal_server_error
    end
  end

  # 現在のユーザー情報を取得
  def me
    if current_user
      render json: {
        user: {
          id: current_user.id,
          email: current_user.email,
          name: current_user.name,
          avatar_url: current_user.avatar_url
        }
      }, status: :ok
    else
      render json: { error: 'ユーザーが見つかりません' }, status: :unauthorized
    end
  end

  # ログアウト (JWTはstatelessなので、フロントエンド側でトークンを削除)
  def logout
    render json: { message: 'ログアウトしました' }, status: :ok
  end

  private

  def verify_google_token(token)
    return nil if token.blank?
    
    # Google OAuth2 APIを使用してトークンを検証
    response = HTTParty.get(
      "https://oauth2.googleapis.com/tokeninfo", 
      query: { id_token: token },
      timeout: 10 # タイムアウト設定
    )
    
    if response.success?
      user_info = response.parsed_response
      
      # セキュリティ検証を強化
      if valid_google_token?(user_info)
        user_info
      else
        Rails.logger.warn "Invalid Google token: verification failed"
        nil
      end
    else
      Rails.logger.warn "Google token verification failed: #{response.code} #{response.message}"
      nil
    end
  rescue HTTParty::Error, Net::TimeoutError => e
    Rails.logger.error "Google token verification network error: #{e.message}"
    nil
  rescue => e
    Rails.logger.error "Google token verification unexpected error: #{e.message}"
    nil
  end

  def valid_google_token?(user_info)
    return false unless user_info.is_a?(Hash)
    
    # 必須フィールドの存在確認
    required_fields = %w[aud sub email name]
    return false unless required_fields.all? { |field| user_info[field].present? }
    
    # クライアントIDの検証
    expected_client_id = ENV['GOOGLE_CLIENT_ID']
    return false if expected_client_id.blank? || user_info['aud'] != expected_client_id
    
    # トークンの有効期限確認
    exp = user_info['exp'].to_i
    return false if exp <= Time.current.to_i
    
    # メールアドレスの検証済み確認
    return false unless user_info['email_verified'] == 'true' || user_info['email_verified'] == true
    
    # 発行者の確認
    valid_issuers = %w[https://accounts.google.com accounts.google.com]
    return false unless valid_issuers.include?(user_info['iss'])
    
    true
  end
end