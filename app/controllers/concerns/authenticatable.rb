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
    render json: { error: '認証が必要です' }, status: :unauthorized unless @current_user
  end

  def authenticate_optional
    result = AuthorizeApiRequest.call(request.headers)
    @current_user = result[:result]
  end
end