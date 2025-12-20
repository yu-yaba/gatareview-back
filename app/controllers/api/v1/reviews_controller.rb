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
        reviews = @lecture.reviews.includes(:user, :thanks).order(created_at: :asc)

        access_granted = has_review_access?

        reviews_json = reviews.each_with_index.map do |review, index|
          review_data = review.as_json
          review_data['user_id'] = review.user_id
          review_data['user'] = review.user ? review.user.as_json(only: %i[id name avatar_url]) : { id: nil, name: '匿名ユーザー', avatar_url: nil }
          review_data['thanks_count'] = review.thanks.count
          review_data['access_granted'] = access_granted

          unless access_granted
            # 権限がない場合でも、最初に投稿されたレビュー（一覧の先頭）は全文表示する
            unless index.zero?
              # それ以外のコメントは先頭30文字のみ返す（フロントでぼかし表示）
              review_data['content'] = mask_review_content(review.content) if review.content.present?
            end
          end

          review_data
        end

        render json: reviews_json
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
        return false unless current_user
        
        # 現在の期間を取得
        current_period = ReviewPeriod.current_period
        if current_period
          # 期間ベースの権限チェック
          period_reviews_count = current_user.reviews_count_for_period(current_period)
          
          if period_reviews_count >= 1
            return true
          end
        else
          # 期間が設定されていない場合は従来の全体レビュー数ベースで判定
          if current_user.reviews_count >= 1
            return true
          end
        end
        
        false
      end

      # レビューコンテンツを部分的にマスク
      def mask_review_content(content)
        return nil if content.blank?

        content[0, 30]
      end

    end
  end
end
