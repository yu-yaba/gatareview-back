# frozen_string_literal: true

module Api
  module V1
    class LecturesController < ApplicationController
      def index
        page = params[:page]&.to_i || 1
        per_page = 20
        
        # ベースクエリを構築
        @lectures = Lecture.eager_load(:reviews)
        
        # 基本検索（キーワード、学部）
        if params[:search].present?
          search_term = "%#{params[:search]}%"
          @lectures = @lectures.where(
            "title LIKE ? OR lecturer LIKE ?", 
            search_term, search_term
          )
        end
        
        if params[:faculty].present?
          @lectures = @lectures.where(faculty: params[:faculty])
        end
        
        # レビュー詳細項目による検索
        if review_search_params_present?
          lecture_ids = filter_by_review_details
          @lectures = @lectures.where(id: lecture_ids) if lecture_ids.any?
        end
        
        # 総件数を取得（ソート前）
        total_count = @lectures.distinct.count('lectures.id')
        
        # ソート処理とページネーション
        @lectures = apply_sorting_and_pagination(@lectures, page, per_page)

        if @lectures.empty? && page == 1
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
      
      def get_sorted_lecture_ids(lectures_query)
        case params[:sort]
        when 'newest'
          # 最新のレビューがある授業順（レビューのない授業は最後）
          lectures_query.left_joins(:reviews)
                       .group('lectures.id')
                       .order(Arel.sql('MAX(reviews.created_at) DESC'), 'lectures.created_at DESC')
                       .pluck('lectures.id')
        when 'highestRating'
          # 評価が高い順（レビューのない授業は最後）
          lectures_query.left_joins(:reviews)
                       .group('lectures.id')
                       .order(Arel.sql('AVG(reviews.rating) DESC'), 'lectures.created_at DESC')
                       .pluck('lectures.id')
        when 'mostReviewed'
          # レビュー件数順（レビューのない授業は最後）
          lectures_query.left_joins(:reviews)
                       .group('lectures.id')
                       .order(Arel.sql('COUNT(reviews.id) DESC'), 'lectures.created_at DESC')
                       .pluck('lectures.id')
        else
          # デフォルトは作成日順
          lectures_query.order(created_at: :desc).pluck('lectures.id')
        end
      end

      def apply_sorting_and_pagination(lectures_query, page, per_page)
        # ソート処理とページネーション
        sorted_lecture_ids = get_sorted_lecture_ids(lectures_query)
        
        # ページネーション
        offset = (page - 1) * per_page
        paginated_ids = sorted_lecture_ids.slice(offset, per_page) || []

        return [] if paginated_ids.empty?

        # ソートされたIDに基づいて実際のレコードを取得
        lectures = Lecture.eager_load(:reviews).where(id: paginated_ids)
        
        # IDの順序を保持してソート
        lectures.sort_by { |lecture| paginated_ids.index(lecture.id) }
      end
    end
  end
end
