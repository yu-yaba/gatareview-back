# frozen_string_literal: true

module Api
  module V1
    class ReviewsController < ApplicationController
      include Authenticatable
      skip_before_action :authenticate_request, only: %i[index create total latest]
      before_action :authenticate_optional, only: %i[index latest]
      before_action :authenticate_optional_for_create, only: [:create]
      before_action :set_lecture, except: %i[total latest update destroy]

      def create
        unless recaptcha_verified?
          render json: { success: false, message: 'reCAPTCHA認証に失敗しました' }, status: :unprocessable_entity
          return
        end

        review_attributes = review_params
        @review = @lecture.reviews.new(review_attributes)
        @review.user = current_user if current_user
        
        if @review.save
          # レビュー投稿成功時、期間別レビュー数を更新（ログインユーザーの場合のみ）
          if current_user
            current_user.increment_period_review_count!
          end
          
          review_data = @review.as_json(include: { user: { only: %i[id name avatar_url] } })
          review_data['user_id'] = @review.user_id
          render json: { 
            success: true, 
            review: review_data
          }, status: :created
        else
          render json: { success: false, errors: @review.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def index
        reviews = @lecture.reviews.includes(:user, :thanks)
        
        # レビュー閲覧権限をチェック
        if has_review_access?
          # 権限がある場合：完全なレビューデータを返す
          reviews_json = reviews.map do |review|
            review_data = review.as_json
            review_data['user_id'] = review.user_id
            review_data['user'] = review.user ? review.user.as_json(only: %i[id name avatar_url]) : { id: nil, name: '匿名ユーザー', avatar_url: nil }
            review_data['thanks_count'] = review.thanks.count
            review_data['access_granted'] = true
            review_data
          end
          render json: reviews_json
        else
          # 権限がない場合：部分的なレビューデータを返す（コメントを制限）
          reviews_json = reviews.map do |review|
            review_data = review.as_json
            review_data['user_id'] = review.user_id
            review_data['user'] = review.user ? review.user.as_json(only: %i[id name avatar_url]) : { id: nil, name: '匿名ユーザー', avatar_url: nil }
            review_data['thanks_count'] = review.thanks.count
            review_data['access_granted'] = false
            # コメントは部分的にマスク（フロントエンドでの処理と一致させる）
            review_data['content'] = mask_review_content(review.content) if review.content.present?
            review_data
          end
          render json: reviews_json
        end
      end

      def total
        total_reviews = Review.count
        render json: { count: total_reviews }
      end

      def update
        @review = Review.find(params[:id])
        
        # 投稿者本人かチェック
        unless @review.user == current_user
          render json: { error: '他のユーザーのレビューは編集できません' }, status: :forbidden
          return
        end
        
        if @review.update(review_params)
          review_data = @review.as_json(include: { user: { only: %i[id name avatar_url] } })
          review_data['user_id'] = @review.user_id
          render json: { 
            success: true, 
            review: review_data
          }
        else
          render json: { success: false, errors: @review.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @review = Review.find(params[:id])
        
        # 投稿者本人かチェック
        unless @review.user == current_user
          render json: { error: '他のユーザーのレビューは削除できません' }, status: :forbidden
          return
        end
        
        if @review.destroy
          # レビュー削除時、期間別レビュー数を減少
          current_user.decrement_period_review_count!
          render json: { success: true, message: 'レビューを削除しました' }
        else
          render json: { success: false, message: 'レビューの削除に失敗しました' }, status: :unprocessable_entity
        end
      end

      def latest
        @reviews = Review.includes(:lecture, :user).order(created_at: :desc).limit(4)
        if @reviews.any?
          access_granted = has_review_access?

          reviews_json = @reviews.map do |review|
            review_data = review.as_json(only: %i[id rating created_at])
            review_data['content'] = access_granted ? review.content : mask_review_content(review.content)
            review_data['lecture'] = review.lecture.as_json(only: %i[id title lecturer faculty])
            review_data['user'] = review.user ? review.user.as_json(only: %i[id name avatar_url]) : { id: nil, name: '匿名ユーザー', avatar_url: nil }
            review_data['access_granted'] = access_granted
            review_data
          end
          render json: reviews_json
        else
          render json: { error: 'レビューが見つかりません。' }, status: :not_found
        end
      end

      private


      def set_lecture
        @lecture = Lecture.find(params[:lecture_id])
      end

      def review_params
        params.require(:review).permit(:rating, :content, :period_year, :period_term, :textbook, :attendance,
                                       :grading_type, :content_difficulty, :content_quality)
      end
      
      def recaptcha_verified?
        # テスト環境は外部通信しない
        return true if Rails.env.test?

        # 本番環境では必須。開発環境は未設定でも動作できるようにスキップ可能にする。
        if ENV['RECAPTCHA_SECRET_KEY'].blank?
          Rails.logger.error('RECAPTCHA_SECRET_KEY is not set') if Rails.env.production?
          return !Rails.env.production?
        end
        
        return false if params[:token].blank?

        verifier = RecaptchaVerifier.new(params[:token], 'submit', 0.5)
        verifier.verify
      end

      # レビュー閲覧権限をチェック（期間ベース対応）
      def has_review_access?
        Rails.logger.info "=== PERIOD-BASED REVIEW ACCESS CHECK ==="
        Rails.logger.info "Current user: #{current_user&.id}"
        
        return false unless current_user
        
        # 現在の期間を取得
        current_period = ReviewPeriod.current_period
        if current_period
          # 期間ベースの権限チェック
          period_reviews_count = current_user.reviews_count_for_period(current_period)
          Rails.logger.info "Period: #{current_period.period_name}"
          Rails.logger.info "Period reviews count: #{period_reviews_count}"
          
          if period_reviews_count >= 1
            Rails.logger.info "✅ Access granted: User has #{period_reviews_count} reviews in current period"
            return true
          end
        else
          # 期間が設定されていない場合は従来の全体レビュー数ベースで判定
          Rails.logger.info "No active period found, using global reviews count: #{current_user.reviews_count}"
          if current_user.reviews_count >= 1
            Rails.logger.info "✅ Access granted: User has #{current_user.reviews_count} total reviews"
            return true
          end
        end
        
        Rails.logger.info "❌ Access denied: Insufficient reviews for current period"
        false
      end

      # レビューコンテンツを部分的にマスク
      def mask_review_content(content)
        return nil if content.blank?
        
        # 短いコメントの場合（50文字以下）は30%まで表示
        if content.length <= 50
          visible_length = (content.length * 0.3).floor
          content[0, visible_length] + "..." if visible_length > 0
        else
          # 長いコメントの場合は1行目の半分まで表示
          first_line_end = content.index("\n") || [content.length, 80].min
          first_line = content[0, first_line_end]
          visible_length = (first_line.length * 0.5).floor
          if visible_length > 0
            content[0, visible_length] + "..."
          else
            "..."
          end
        end
      end

    end
  end
end
