module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request
    attr_reader :current_user
  end

  private

  def authenticate_request
    result = AuthorizeApiRequest.call(request.headers)
    @current_user = result[:result]

    # セキュリティ/ノイズ対策: 本番環境では認証の詳細ログを出さない
    if Rails.env.development?
      Rails.logger.debug "Authorization header present: #{request.headers['Authorization'].present?}"
      Rails.logger.debug "Current user authenticated: #{@current_user&.id.present? || false}"
    end

    render json: { error: '認証が必要です' }, status: :unauthorized unless @current_user
  end

  def authenticate_optional
    result = AuthorizeApiRequest.call(request.headers)
    @current_user = result[:result]
  end

  def authenticate_optional_for_create
    authenticate_optional
  end
end
