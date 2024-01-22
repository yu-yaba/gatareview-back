# frozen_string_literal: true

module Api
  module V1
    class LecturesController < ApplicationController
      def index
        query_conditions = {}

        query_conditions[:faculty] = params[:faculty] if params[:faculty].present?

        query_conditions[:title] = params[:searchWord] if params[:searchWord].present?

        if query_conditions.empty?
          render json: { error: 'Either faculty or searchWord must be specified.' }, status: 400
          return
        end

        @lectures = Lecture.includes(:reviews)
                           .where('faculty LIKE :faculty OR title LIKE :searchWord', faculty: "%#{query_conditions[:faculty]}%", searchWord: "%#{query_conditions[:title]}%")

        lecture_ids = @lectures.pluck(:id)
        avg_ratings = Review.where(lecture_id: lecture_ids).group(:lecture_id).average(:rating)

        @lectures_json = @lectures.map do |lecture|
          lecture_attributes = lecture.attributes
          avg_rating = avg_ratings[lecture.id.to_s] || 0
          lecture_attributes[:avg_rating] = avg_rating.round(1)
          lecture_attributes[:reviews] = lecture.reviews.map do |review|
            {
              id: review.id,
              content: review.content,
              rating: review.rating,
              created_at: review.created_at,
              updated_at: review.updated_at
            }
          end
          lecture_attributes
        end

        render json: @lectures_json
      end

      def show
        @lecture = Lecture.find(params[:id])
        render json: @lecture
      end

      def create
        @lecture = Lecture.new(lecture_params)

        if @lecture.save
          render json: @lecture, status: :created
        else
          render json: @lecture.errors, status: :unprocessable_entity
        end
      end

      private

      def lecture_params
        params.require(:lecture).permit(:title, :lecturer, :faculty)
      end
    end
  end
end
