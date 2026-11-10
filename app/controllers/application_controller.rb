# frozen_string_literal: true

class ApplicationController < ActionController::API
  before_action :prevent_api_response_caching

  # 例外から作る既定のエラー応答（"Not Found" / "Bad Request"）は英語なので、
  # 画面にそのまま出せる日本語で返す。ステータスは既定と同じ。
  rescue_from ActiveRecord::RecordNotFound do |error|
    model = error.model.to_s.safe_constantize
    subject = model.respond_to?(:model_name) ? model.model_name.human : 'データ'
    render json: { error: "#{subject}が見つかりません" }, status: :not_found
  end

  rescue_from ActionController::ParameterMissing, ActionDispatch::Http::Parameters::ParseError do
    render json: { error: 'リクエストの形式が正しくありません' }, status: :bad_request
  end

  private

  def prevent_api_response_caching
    response.headers['Cache-Control'] = 'private, no-store' if request.path.start_with?('/api/')
  end
end
