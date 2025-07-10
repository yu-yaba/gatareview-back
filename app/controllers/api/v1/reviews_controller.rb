# frozen_string_literal: true

module Api
  module V1
    class ReviewsController < ApplicationController
      include Authenticatable
      skip_before_action :authenticate_request, only: %i[index total latest create]
      before_action :set_lecture, except: %i[total latest]

      def create
        token = params[:token]
        review_attributes = review_params

        verifier = RecaptchaVerifier.new(token, 'submit', 0.5)

        if verifier.verify
          # reCAPTCHAスコアが閾値以上の場合、レビューを即時に保存
          create_review(review_attributes)
        else
          render json: { success: false, message: 'reCAPTCHA認証に失敗しました。' }, status: :unprocessable_entity
        end
      end

      def index
        reviews = @lecture.reviews.includes(:user)
        render json: reviews.as_json(include: { user: { only: %i[id name avatar_url] } })
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
          render json: { 
            success: true, 
            review: @review.as_json(include: { user: { only: %i[id name avatar_url] } })
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
          render json: { success: true, message: 'レビューを削除しました' }
        else
          render json: { success: false, message: 'レビューの削除に失敗しました' }, status: :unprocessable_entity
        end
      end

      def latest
        @reviews = Review.includes(:lecture, :user).order(created_at: :desc).limit(4)
        if @reviews.any?
          render json: @reviews.as_json(
            include: { 
              lecture: { only: %i[id title lecturer] },
              user: { only: %i[id name avatar_url] }
            },
            only: %i[id rating content created_at]
          )
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

      def create_review(attributes)
        @review = @lecture.reviews.new(attributes)
        @review.user = current_user if current_user # 認証されている場合のみユーザーを設定
        
        if @review.save
          render json: { 
            success: true, 
            review: @review.as_json(include: { user: { only: %i[id name] } })
          }, status: :created
        else
          render json: { success: false, errors: @review.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end
end
