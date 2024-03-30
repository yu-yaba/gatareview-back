# frozen_string_literal: true

module Api
  module V1
    class ReviewsController < ApplicationController
      before_action :set_lecture, except: [:total, :latest]

      def index
        reviews = @lecture.reviews
        render json: reviews
      end

      def create
        @review = @lecture.reviews.new(review_params)

        if @review.save
          render json: @review, status: :created
        else
          render json: @review.errors, status: :unprocessable_entity
        end
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
    end
  end
end
