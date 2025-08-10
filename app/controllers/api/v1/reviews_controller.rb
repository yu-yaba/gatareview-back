# frozen_string_literal: true

module Api
  module V1
    class ReviewsController < ApplicationController
      include Authenticatable
      skip_before_action :authenticate_request, only: %i[index create total latest]
      before_action :authenticate_optional_for_create, only: [:create]
      before_action :set_lecture, except: %i[total latest update destroy]

      def create
        review_attributes = review_params
        @review = @lecture.reviews.new(review_attributes)
        @review.user = current_user if current_user
        
        if @review.save
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
        reviews_json = reviews.map do |review|
          review_data = review.as_json
          review_data['user_id'] = review.user_id
          review_data['user'] = review.user ? review.user.as_json(only: %i[id name avatar_url]) : { id: nil, name: '匿名ユーザー', avatar_url: nil }
          review_data['thanks_count'] = review.thanks.count
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
          render json: { success: true, message: 'レビューを削除しました' }
        else
          render json: { success: false, message: 'レビューの削除に失敗しました' }, status: :unprocessable_entity
        end
      end

      def latest
        @reviews = Review.includes(:lecture, :user).order(created_at: :desc).limit(4)
        if @reviews.any?
          reviews_json = @reviews.map do |review|
            review_data = review.as_json(only: %i[id rating content created_at])
            review_data['lecture'] = review.lecture.as_json(only: %i[id title lecturer faculty])
            review_data['user'] = review.user ? review.user.as_json(only: %i[id name avatar_url]) : { id: nil, name: '匿名ユーザー', avatar_url: nil }
            review_data
          end
          render json: reviews_json
        else
          render json: { error: 'レビューが見つかりません。' }, status: :not_found
        end
      end

      private

      def authenticate_optional_for_create
        authenticate_optional
      end

      def set_lecture
        @lecture = Lecture.find(params[:lecture_id])
      end

      def review_params
        params.require(:review).permit(:rating, :content, :period_year, :period_term, :textbook, :attendance,
                                       :grading_type, :content_difficulty, :content_quality)
      end

    end
  end
end
