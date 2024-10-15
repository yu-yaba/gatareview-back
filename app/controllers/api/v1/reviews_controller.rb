# frozen_string_literal: true

module Api
  module V1
    class ReviewsController < ApplicationController
      before_action :set_lecture, except: [:total]

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
        reviews = @lecture.reviews
        render json: reviews
      end

      def total
        total_reviews = Review.count
        render json: { count: total_reviews }
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
        if @review.save
          render json: @review, status: :created
        else
          render json: @review.errors, status: :unprocessable_entity
        end
      end
    end
  end
end
