module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request
    attr_reader :current_user
  end

  private

  def authenticate_request
    Rails.logger.info "=== AUTHENTICATION DEBUG ==="
    Rails.logger.info "Request headers: #{request.headers.to_h.select { |k, v| k.match(/^HTTP_/) || k == 'Authorization' }}"
    Rails.logger.info "Authorization header: #{request.headers['Authorization']}"
    
    result = AuthorizeApiRequest.call(request.headers)
    @current_user = result[:result]
    
    Rails.logger.info "Current user: #{@current_user&.id || 'nil'}"
    Rails.logger.info "==============================="
    
    render json: { error: '認証が必要です' }, status: :unauthorized unless @current_user
  end

  def authenticate_optional
    result = AuthorizeApiRequest.call(request.headers)
    @current_user = result[:result]
  end
end