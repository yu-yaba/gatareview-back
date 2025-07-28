class Api::V1::AuthController < ApplicationController
  include Authenticatable
  skip_before_action :authenticate_request, only: [:google_oauth]
  before_action :authenticate_optional, only: [:me]

  # Google OAuth認証
  def google_oauth
    begin
      Rails.logger.info "=== Google OAuth Request ==="
      Rails.logger.info "Request params: #{params.inspect}"
      Rails.logger.info "Google token present: #{params[:token].present?}"
      
      # Googleトークンを検証
      google_user_info = verify_google_token(params[:token])
      Rails.logger.info "Google user info verification result: #{google_user_info.present? ? 'SUCCESS' : 'FAILED'}"
      
      if google_user_info
        # ユーザーを作成または取得
        user = User.from_google_oauth(google_user_info)
        Rails.logger.info "User creation/retrieval: #{user.persisted? ? 'SUCCESS' : 'FAILED'}"
        
        if user.persisted?
          # JWTトークンを生成
          expiration = params[:remember] ? 30.days.from_now : 7.days.from_now
          token = JsonWebToken.encode(user.jwt_payload, expiration)
          Rails.logger.info "JWT token generated: #{token.present? ? 'SUCCESS' : 'FAILED'}"
          Rails.logger.info "JWT token generated successfully" if token
          
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
          Rails.logger.error "User persistence failed: #{user.errors.full_messages}"
          render json: { error: 'ユーザーの作成に失敗しました' }, status: :unprocessable_entity
        end
      else
        Rails.logger.error "Google token verification failed"
        render json: { error: '無効なGoogleトークンです' }, status: :unauthorized
      end
    rescue => e
      Rails.logger.error "Google OAuth error: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
      render json: { error: '認証に失敗しました' }, status: :internal_server_error
    ensure
      Rails.logger.info "==============================="
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
    
    Rails.logger.info "=== Google Token Verification START ==="
    Rails.logger.info "Token received for verification"
    Rails.logger.info "Google Client ID: #{ENV['GOOGLE_CLIENT_ID'] ? 'Set' : 'NOT SET'}"
    Rails.logger.info "Expected Client ID: #{ENV['GOOGLE_CLIENT_ID']}"
    
    # Google OAuth2 APIを使用してトークンを検証
    url = "https://oauth2.googleapis.com/tokeninfo"
    query_params = { id_token: token }
    
    Rails.logger.info "Making request to: #{url}"
    Rails.logger.info "Query params: #{query_params.inspect}"
    
    response = HTTParty.get(url, query: query_params, timeout: 10)
    
    Rails.logger.info "Google API response status: #{response.code}"
    Rails.logger.info "Google API response headers: #{response.headers}"
    Rails.logger.info "Google API response body: #{response.body}"
    
    if response.success?
      user_info = response.parsed_response
      Rails.logger.info "Google user info keys: #{user_info.keys}"
      Rails.logger.info "Google user info aud: #{user_info['aud']}"
      Rails.logger.info "Google user info iss: #{user_info['iss']}"
      Rails.logger.info "Google user info exp: #{user_info['exp']} (#{Time.at(user_info['exp'].to_i)})"
      Rails.logger.info "Current time: #{Time.current}"
      
      # セキュリティ検証を強化
      if valid_google_token?(user_info)
        Rails.logger.info "✅ Google token validation: SUCCESS"
        user_info
      else
        Rails.logger.warn "❌ Google token validation: FAILED"
        nil
      end
    else
      Rails.logger.error "❌ Google token verification failed"
      Rails.logger.error "Response code: #{response.code}"
      Rails.logger.error "Response message: #{response.message}"
      Rails.logger.error "Response body: #{response.body}"
      nil
    end
  rescue HTTParty::Error, Net::TimeoutError => e
    Rails.logger.error "❌ Google token verification network error: #{e.message}"
    Rails.logger.error "Error class: #{e.class}"
    nil
  rescue => e
    Rails.logger.error "❌ Google token verification unexpected error: #{e.message}"
    Rails.logger.error "Error class: #{e.class}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
    nil
  ensure
    Rails.logger.info "=== Google Token Verification END ==="
  end

  def valid_google_token?(user_info)
    Rails.logger.info "=== Token Validation START ==="
    
    unless user_info.is_a?(Hash)
      Rails.logger.error "❌ User info is not a hash: #{user_info.class}"
      return false
    end
    
    # 必須フィールドの存在確認
    required_fields = %w[aud sub email]
    missing_fields = required_fields.reject { |field| user_info[field].present? }
    
    if missing_fields.any?
      Rails.logger.error "❌ Missing required fields: #{missing_fields}"
      Rails.logger.info "Available fields: #{user_info.keys}"
      return false
    end
    Rails.logger.info "✅ Required fields present"
    
    # クライアントIDの検証
    expected_client_id = ENV['GOOGLE_CLIENT_ID']
    actual_client_id = user_info['aud']
    
    Rails.logger.info "Expected client ID: #{expected_client_id}"
    Rails.logger.info "Actual client ID: #{actual_client_id}"
    Rails.logger.info "Client ID match: #{expected_client_id == actual_client_id}"
    
    if expected_client_id.blank?
      Rails.logger.error "❌ GOOGLE_CLIENT_ID environment variable not set"
      return false
    end
    
    if actual_client_id != expected_client_id
      Rails.logger.error "❌ Client ID mismatch"
      return false
    end
    Rails.logger.info "✅ Client ID valid"
    
    # トークンの有効期限確認
    exp = user_info['exp'].to_i
    current_time = Time.current.to_i
    
    Rails.logger.info "Token expiry: #{exp} (#{Time.at(exp)})"
    Rails.logger.info "Current time: #{current_time} (#{Time.at(current_time)})"
    Rails.logger.info "Time until expiry: #{exp - current_time} seconds"
    
    if exp <= current_time
      Rails.logger.error "❌ Token expired"
      return false
    end
    Rails.logger.info "✅ Token not expired"
    
    # メールアドレスの検証済み確認
    email_verified = user_info['email_verified']
    Rails.logger.info "Email verified value: #{email_verified} (#{email_verified.class})"
    
    unless email_verified == 'true' || email_verified == true
      Rails.logger.error "❌ Email not verified"
      return false
    end
    Rails.logger.info "✅ Email verified"
    
    # 発行者の確認
    issuer = user_info['iss']
    valid_issuers = %w[https://accounts.google.com accounts.google.com]
    
    Rails.logger.info "Token issuer: #{issuer}"
    Rails.logger.info "Valid issuers: #{valid_issuers}"
    
    unless valid_issuers.include?(issuer)
      Rails.logger.error "❌ Invalid issuer"
      return false
    end
    Rails.logger.info "✅ Issuer valid"
    
    Rails.logger.info "=== Token Validation SUCCESS ==="
    true
  rescue => e
    Rails.logger.error "❌ Token validation error: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(3).join('\n')}"
    false
  end
end