module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request
    attr_reader :current_user
  end

  private

  def authenticate_request
    Rails.logger.info "=== AUTHENTICATION DEBUG ==="
    Rails.logger.info "Authorization header present: #{request.headers['Authorization'].present?}"
    
    result = AuthorizeApiRequest.call(request.headers)
    @current_user = result[:result]
    
    Rails.logger.info "Current user authenticated: #{@current_user&.id.present? || false}"
    Rails.logger.info "==============================="
    
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