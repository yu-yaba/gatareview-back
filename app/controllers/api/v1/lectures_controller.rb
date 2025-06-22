# frozen_string_literal: true

module Api
  module V1
    class LecturesController < ApplicationController
      def index
        page = params[:page]&.to_i || 1
        per_page = 20
        
        # 検索パラメータがない場合は空の結果を返す
        unless params[:search].present? || params[:faculty].present? || review_search_params_present?
          render json: { 
            lectures: [], 
            pagination: {
              current_page: page,
              total_pages: 0,
              total_count: 0,
              per_page: per_page
            }
          }
          return
        end
        
        # 効率的なクエリ構築（eager_loadは必要な場合のみ）
        @lectures = Lecture.all
        
        # 基本検索（キーワード、学部）
        if params[:search].present?
          @lectures = @lectures.search_by_title_and_lecturer(params[:search])
        end
        
        if params[:faculty].present?
          @lectures = @lectures.where(faculty: params[:faculty])
        end
        
        # レビュー詳細項目による検索
        if review_search_params_present?
          lecture_ids = filter_by_review_details
          @lectures = @lectures.where(id: lecture_ids) if lecture_ids.any?
        end
        
        # 総件数を効率的に取得
        total_count = @lectures.count
        
        # ページネーション（limit/offsetを使用）
        offset = (page - 1) * per_page
        @lectures = @lectures.limit(per_page).offset(offset)

        # 結果が空の場合
        if @lectures.empty?
          render json: { 
            lectures: [], 
            pagination: {
              current_page: page,
              total_pages: (total_count.to_f / per_page).ceil,
              total_count: total_count,
              per_page: per_page
            }
          }
          return
        end

        # JSON化（N+1問題を回避）
        @lectures_json = Lecture.as_json_reviews(@lectures)
        
        total_pages = (total_count.to_f / per_page).ceil

        render json: {
          lectures: @lectures_json,
          pagination: {
            current_page: page,
            total_pages: total_pages,
            total_count: total_count,
            per_page: per_page
          }
        }
      end

      def show
        @lecture = Lecture.find_by(id: params[:id])

        if @lecture
          render json: @lecture
        else
          render json: { error: '指定された講義は存在しません。' }, status: :not_found
        end
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
      
      def review_search_params_present?
        params[:period_year].present? || params[:period_term].present? ||
        params[:textbook].present? || params[:attendance].present? ||
        params[:grading_type].present? || params[:content_difficulty].present? ||
        params[:content_quality].present?
      end
      
      def filter_by_review_details
        review_query = Review.all
        
        review_query = review_query.where(period_year: params[:period_year]) if params[:period_year].present?
        review_query = review_query.where(period_term: params[:period_term]) if params[:period_term].present?
        review_query = review_query.where(textbook: params[:textbook]) if params[:textbook].present?
        review_query = review_query.where(attendance: params[:attendance]) if params[:attendance].present?
        review_query = review_query.where(grading_type: params[:grading_type]) if params[:grading_type].present?
        review_query = review_query.where(content_difficulty: params[:content_difficulty]) if params[:content_difficulty].present?
        review_query = review_query.where(content_quality: params[:content_quality]) if params[:content_quality].present?
        
        review_query.distinct.pluck(:lecture_id)
      end
    end
  end
end
