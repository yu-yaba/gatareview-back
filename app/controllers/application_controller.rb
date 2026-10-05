# frozen_string_literal: true

class ApplicationController < ActionController::API
  before_action :prevent_api_response_caching

  private

  def prevent_api_response_caching
    response.headers['Cache-Control'] = 'private, no-store' if request.path.start_with?('/api/')
  end
end
