# frozen_string_literal: true

module Api
  module V1
    class LecturesController < ApplicationController
      def index
        page = [params[:page]&.to_i || 1, 1].max
        per_page = 20

        # 効率的なクエリ構築
        @lectures = Lecture.all

        # 検索条件とソート処理
        has_search_params = params[:search].present? || params[:faculty].present? || review_search_params_present?
        sort_param = params[:sort] || 'newest'
        
        # ソート処理
        case sort_param
        when 'highestRating'
          # 評価の高い順（レビューがある授業のみ）
          @lectures = @lectures.joins(:reviews)
                               .group('lectures.id')
                               .order('AVG(reviews.rating) DESC, COUNT(reviews.id) DESC')
        when 'mostReviewed'
          # レビュー数の多い順（レビューがある授業のみ）
          @lectures = @lectures.joins(:reviews)
                               .group('lectures.id')
                               .order('COUNT(reviews.id) DESC')
        when 'newest'
          # 最新レビュー順（レビューの最新投稿日時順）
          @lectures = @lectures.left_joins(:reviews)
                               .group('lectures.id')
                               .order('MAX(reviews.created_at) DESC, lectures.created_at DESC')
        end

        # 基本検索（キーワード、学部）
        @lectures = @lectures.search_by_title_and_lecturer(params[:search]) if params[:search].present?

        @lectures = @lectures.where(faculty: params[:faculty]) if params[:faculty].present?

        # レビュー詳細項目による検索（JOINを使って効率化）
        @lectures = filter_lectures_by_review_details(@lectures) if review_search_params_present?

        # GROUP BYがない場合のみ決定的なソート（IDでソート）を追加
        unless ['highestRating', 'mostReviewed', 'newest'].include?(sort_param)
          @lectures = @lectures.order(:id)
        end

        # 総件数を効率的に取得（詳細検索やGROUP BYの場合を適切に処理）
        if review_search_params_present?
          # 詳細検索の場合は専用のカウント処理
          total_count = count_filtered_lectures_by_review_details
        elsif ['highestRating', 'mostReviewed', 'newest'].include?(sort_param)
          # GROUP BYを使用している場合、countの結果は異なる
          count_result = @lectures.except(:order, :limit, :offset).count
          total_count = count_result.is_a?(Hash) ? count_result.size : count_result
        else
          # 通常のcount（GROUP BYなし）
          total_count = @lectures.except(:order, :limit, :offset, :group).count
        end

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

      def filter_lectures_by_review_details(lectures)
        conditions, params_values = build_review_search_conditions
        return lectures if conditions.empty?

        # JOINクエリで効率的に検索（DISTINCTを使う場合はSELECTに必要なカラムを明示）
        lectures.joins(:reviews)
                .where(conditions.join(' AND '), *params_values)
                .select('lectures.*')
                .distinct
      end

      def count_filtered_lectures_by_review_details
        conditions, params_values = build_review_search_conditions
        return 0 if conditions.empty?

        # 基本クエリを構築
        base_query = Lecture.all

        # 基本検索（キーワード、学部）の条件を追加
        base_query = base_query.search_by_title_and_lecturer(params[:search]) if params[:search].present?
        base_query = base_query.where(faculty: params[:faculty]) if params[:faculty].present?

        # 詳細検索の条件を追加してDISTINCTでカウント
        base_query.joins(:reviews)
                  .where(conditions.join(' AND '), *params_values)
                  .distinct
                  .count
      end

      def build_review_search_conditions
        conditions = []
        params_values = []

        if params[:period_year].present?
          conditions << 'reviews.period_year = ?'
          params_values << params[:period_year]
        end

        if params[:period_term].present?
          conditions << 'reviews.period_term = ?'
          params_values << params[:period_term]
        end

        if params[:textbook].present?
          conditions << 'reviews.textbook = ?'
          params_values << params[:textbook]
        end

        if params[:attendance].present?
          conditions << 'reviews.attendance = ?'
          params_values << params[:attendance]
        end

        if params[:grading_type].present?
          conditions << 'reviews.grading_type = ?'
          params_values << params[:grading_type]
        end

        if params[:content_difficulty].present?
          conditions << 'reviews.content_difficulty = ?'
          params_values << params[:content_difficulty]
        end

        if params[:content_quality].present?
          conditions << 'reviews.content_quality = ?'
          params_values << params[:content_quality]
        end

        [conditions, params_values]
      end
    end
  end
end
