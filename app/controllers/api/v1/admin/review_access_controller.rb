# frozen_string_literal: true

module Api
  module V1
    module Admin
      class ReviewAccessController < ApplicationController
        include Authenticatable

        before_action :require_admin_privileges

        def show
          render json: review_access_payload
        end

        def update
          new_value = normalized_restriction_value
          return render_invalid_value if new_value.nil?

          setting = SiteSetting.current!

          if setting.update(lecture_review_restriction_enabled: new_value, last_updated_by: current_user)
            render json: review_access_payload(setting)
          else
            render json: { errors: setting.errors.full_messages }, status: :unprocessable_entity
          end
        end

        private

        def require_admin_privileges
          render json: { error: '管理者権限が必要です' }, status: :forbidden unless current_user&.admin?
        end

        def review_access_payload(setting = SiteSetting.current)
          {
            lecture_review_restriction_enabled: setting.lecture_review_restriction_enabled,
            updated_at: setting.updated_at,
            last_updated_by: setting.last_updated_by&.as_json(only: %i[id name email])
          }
        end

        def normalized_restriction_value
          value = review_access_params[:lecture_review_restriction_enabled]
          return nil unless [true, false, 'true', 'false'].include?(value)

          ActiveModel::Type::Boolean.new.cast(value)
        end

        def review_access_params
          params.require(:review_access).permit(:lecture_review_restriction_enabled)
        end

        def render_invalid_value
          render json: { errors: ['lecture_review_restriction_enabled は true または false を指定してください'] },
                 status: :unprocessable_entity
        end
      end
    end
  end
end
