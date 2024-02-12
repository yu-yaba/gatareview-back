# frozen_string_literal: true

module Api
  module V1
    class LecturesController < ApplicationController
      def index
        @lectures = Lecture.preload(:reviews)
    
        render json: { error: 'Either faculty or searchWord must be specified.' }, status: 400 if @lectures.empty?

        @lectures_json = Lecture.as_json_reviews(@lectures)

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
