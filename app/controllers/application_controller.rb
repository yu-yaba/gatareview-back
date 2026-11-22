# frozen_string_literal: true

class ApplicationController < ActionController::API
  # PostgreSQL は NUL 文字（U+0000）を含む文字列を受け付けず、pg が ArgumentError を上げて 500 になる。
  # 認証や DB への問い合わせより前に、形式の誤りとして 400 で返す。
  prepend_before_action :reject_null_bytes
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

  def reject_null_bytes
    return unless contains_null_byte?(params.to_unsafe_h)

    render json: { error: 'リクエストの形式が正しくありません' }, status: :bad_request
  end

  def contains_null_byte?(value)
    case value
    when String then value.include?("\0")
    when Hash then value.any? { |key, item| contains_null_byte?(key.to_s) || contains_null_byte?(item) }
    when Array then value.any? { |item| contains_null_byte?(item) }
    else false
    end
  end

  def prevent_api_response_caching
    response.headers['Cache-Control'] = 'private, no-store' if request.path.start_with?('/api/')
  end
end
