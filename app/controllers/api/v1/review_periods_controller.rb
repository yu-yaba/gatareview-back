# frozen_string_literal: true

module Api
  module V1
    class ReviewPeriodsController < ApplicationController
      include Authenticatable
      before_action :authenticate_request
      before_action :require_admin_privileges
      before_action :set_review_period, only: [:show, :update, :destroy, :activate, :deactivate]

      def index
        periods = ReviewPeriod.all.order(:start_date)
        render json: periods.as_json(
          only: [:id, :period_name, :start_date, :end_date, :is_active, :created_at, :updated_at],
          methods: [:within_period?]
        )
      end

      def show
        period_data = @review_period.as_json(
          only: [:id, :period_name, :start_date, :end_date, :is_active, :created_at, :updated_at],
          methods: [:within_period?]
        )
        period_data[:user_count] = @review_period.user_review_period_counts.count
        period_data[:total_reviews] = @review_period.user_review_period_counts.sum(:reviews_count)
        
        render json: period_data
      end

      def create
        @review_period = ReviewPeriod.new(review_period_params)
        
        if @review_period.save
          render json: @review_period.as_json(
            only: [:id, :period_name, :start_date, :end_date, :is_active, :created_at, :updated_at]
          ), status: :created
        else
          render json: { errors: @review_period.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @review_period.update(review_period_params)
          render json: @review_period.as_json(
            only: [:id, :period_name, :start_date, :end_date, :is_active, :created_at, :updated_at]
          )
        else
          render json: { errors: @review_period.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        if @review_period.destroy
          render json: { message: '期間を削除しました' }
        else
          render json: { errors: @review_period.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def activate
        if @review_period.activate!
          render json: { 
            message: "期間 '#{@review_period.period_name}' をアクティブにしました",
            period: @review_period.as_json(only: [:id, :period_name, :is_active])
          }
        else
          render json: { errors: @review_period.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def deactivate
        if @review_period.deactivate!
          render json: { 
            message: "期間 '#{@review_period.period_name}' を無効にしました",
            period: @review_period.as_json(only: [:id, :period_name, :is_active])
          }
        else
          render json: { errors: @review_period.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def current
        current_period = ReviewPeriod.current_period
        if current_period
          period_data = current_period.as_json(
            only: [:id, :period_name, :start_date, :end_date, :is_active, :created_at, :updated_at],
            methods: [:within_period?]
          )
          period_data[:user_count] = current_period.user_review_period_counts.count
          period_data[:total_reviews] = current_period.user_review_period_counts.sum(:reviews_count)
          
          render json: period_data
        else
          render json: { message: '現在アクティブな期間はありません' }, status: :not_found
        end
      end

      private

      def set_review_period
        @review_period = ReviewPeriod.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: '期間が見つかりません' }, status: :not_found
      end

      def review_period_params
        params.require(:review_period).permit(:period_name, :start_date, :end_date, :is_active)
      end

      def require_admin_privileges
        # 管理者権限チェック（環境変数 ADMIN_EMAILS/ADMIN_EMAIL でホワイトリスト管理）
        unless current_user&.admin?
          render json: { error: '管理者権限が必要です' }, status: :forbidden
          return
        end
      end
    end
  end
end
