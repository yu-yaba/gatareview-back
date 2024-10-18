# frozen_string_literal: true

module Api
  module V1
    class ReviewsController < ApplicationController
      before_action :set_lecture, except: [:total, :latest]

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

      def latest
        @reviews = Review.includes(:lecture).order(created_at: :desc).limit(3)
        puts @reviews
        if @reviews.any?
          render json: @reviews.as_json(include: { lecture: { only: [:id, :title, :lecturer] }}, only: [:id, :rating, :content, :created_at])
        else
          render json: { error: "レビューが見つかりません。" }, status: :not_found
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
        if @review.save
          render json: { success: true, review: @review }, status: :created
        else
          render json: { success: false, errors: @review.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end
end
