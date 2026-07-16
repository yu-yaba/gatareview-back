# frozen_string_literal: true

module Api
  module V1
    class LecturesController < ApplicationController
      include Authenticatable
      skip_before_action :authenticate_request, only: %i[index show popular no_reviews]
      before_action :require_admin_privileges, only: [:create]

      def index
        page = [params[:page]&.to_i || 1, 1].max
        per_page = 20

        # 効率的なクエリ構築
        @lectures = Lecture.canonical

        # 検索条件とソート処理
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
        @lectures = filter_lectures_by_offering_details(@lectures) if offering_search_params_present?

        # GROUP BYがない場合のみ決定的なソート（IDでソート）を追加
        unless ['highestRating', 'mostReviewed', 'newest'].include?(sort_param)
          @lectures = @lectures.order(:id)
        end

        # 総件数を効率的に取得（詳細検索やGROUP BYの場合を適切に処理）
        count_result = @lectures.except(:order, :limit, :offset).count
        total_count = count_result.is_a?(Hash) ? count_result.size : count_result

        # ページネーション（limit/offsetを使用）
        offset = (page - 1) * per_page
        @lectures = @lectures.includes(lecture_offerings: %i[offering_slots lecture_offering_detail]).limit(per_page).offset(offset)

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
        @lecture = Lecture.includes(lecture_offerings: %i[offering_slots lecture_offering_detail]).find_by(id: params[:id])
        @lecture = @lecture.merged_into_lecture if @lecture&.merged_into_lecture

        if @lecture
          render json: @lecture.as_json_with_reviews
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

      def popular
        # レビュー数の多い順に上位4件の講義を取得
        @lectures = Lecture.joins(:reviews)
                          .group('lectures.id')
                          .order('COUNT(reviews.id) DESC')
                          .includes(lecture_offerings: %i[offering_slots lecture_offering_detail])
                          .limit(4)

        if @lectures.any?
          lectures_json = Lecture.as_json_reviews(@lectures)
          render json: { lectures: lectures_json }
        else
          render json: { lectures: [] }
        end
      end

      def no_reviews
        lectures_without_reviews = Lecture.left_joins(:reviews)
                                          .where(reviews: { id: nil })

        limit = 4
        lectures_count = lectures_without_reviews.count
        max_offset = [lectures_count - limit, 0].max
        offset = max_offset.positive? ? SecureRandom.random_number(max_offset + 1) : 0

        @lectures = lectures_without_reviews.order(:id)
                                            .includes(lecture_offerings: %i[offering_slots lecture_offering_detail])
                                            .offset(offset)
                                            .limit(limit)

        if @lectures.any?
          lectures_json = Lecture.as_json_reviews(@lectures)
          render json: { lectures: lectures_json }
        else
          render json: { lectures: [] }
        end
      end

      private

      def lecture_params
        params.require(:lecture).permit(:title, :lecturer, :faculty)
      end

      def require_admin_privileges
        unless current_user&.admin?
          render json: { error: '管理者権限が必要です' }, status: :forbidden
          return
        end
      end

      def review_search_params_present?
        params[:period_year].present? || params[:period_term].present? ||
          params[:academic_year].present? || params[:review_term_code].present? ||
          params[:textbook].present? || params[:attendance].present? ||
          params[:grading_type].present? || params[:content_difficulty].present? ||
          params[:content_quality].present?
      end

      def offering_search_params_present?
        params[:term].present? || params[:day].present? || params[:period].present? || params[:offering_year].present? ||
          offering_detail_params_present?
      end

      def filter_lectures_by_offering_details(lectures)
        year = offering_year
        return Lecture.none unless year

        filtered = lectures.joins(:lecture_offerings)
                           .where(lecture_offerings: { year: year, source_status: 'active' })

        if params[:term].present?
          if params[:term].to_s == 'intensive'
            filtered = filtered.where(
              'lecture_offerings.schedule_kind = :kind OR lecture_offerings.term_code = :term_code',
              kind: 'intensive', term_code: '4'
            )
          elsif params[:term].to_s == 'other'
            filtered = filtered.where(
              'lecture_offerings.schedule_kind = :kind OR lecture_offerings.term_code IN (:term_codes)',
              kind: 'other', term_codes: %w[5 9]
            )
          else
            term_codes = term_codes_for(params[:term])
            return Lecture.none if term_codes.empty?

            filtered = filtered.where(lecture_offerings: { term_code: term_codes })
          end
        end

        if params[:day].present? || params[:period].present?
          filtered = filtered.joins(lecture_offerings: :offering_slots)
          filtered = filtered.where(offering_slots: { day: params[:day].to_i }) if valid_slot_param?(:day)
          filtered = filtered.where(offering_slots: { period: params[:period].to_i }) if valid_slot_param?(:period)
          return Lecture.none if params[:day].present? && !valid_slot_param?(:day)
          return Lecture.none if params[:period].present? && !valid_slot_param?(:period)
        end

        filtered = filter_by_offering_details(filtered) if offering_detail_params_present?

        filtered.distinct
      end

      def offering_year
        return LectureOffering.active.maximum(:year) if params[:offering_year].blank?

        year = Integer(params[:offering_year], 10)
        year.between?(1000, 9999) ? year : nil
      rescue ArgumentError
        nil
      end

      def term_codes_for(term)
        number = Integer(term, 10)
        return [] unless number.between?(1, 4)

        LectureOffering::TERM_EXPANSION.select { |_code, terms| terms.include?(number) }.keys
      rescue ArgumentError
        []
      end

      def offering_detail_params_present?
        %i[credits target_year campus language delivery_method subject_category].any? { |key| params[key].present? }
      end

      def filter_by_offering_details(lectures)
        filtered = lectures.joins(lecture_offerings: :lecture_offering_detail)
        filtered = filtered.where(lecture_offering_details: { credits: params[:credits] }) if params[:credits].present?
        filtered = filtered.where(lecture_offering_details: { campus: params[:campus] }) if params[:campus].present?
        filtered = filtered.where(lecture_offering_details: { language: params[:language] }) if params[:language].present?
        filtered = filtered.where(lecture_offering_details: { delivery_method: params[:delivery_method] }) if params[:delivery_method].present?
        filtered = filtered.where(lecture_offering_details: { subject_category: params[:subject_category] }) if params[:subject_category].present?
        if params[:target_year].present?
          filtered = filtered.where('JSON_CONTAINS(lecture_offering_details.target_years, ?)', [params[:target_year].to_i].to_json)
        end
        filtered
      end

      def valid_slot_param?(name)
        value = Integer(params[name], 10)
        value.between?(1, 7)
      rescue ArgumentError
        false
      end

      def filter_lectures_by_review_details(lectures)
        conditions, params_values = build_review_search_conditions
        return lectures if conditions.empty?

        # JOINクエリで効率的に検索し、複数ReviewによるLectureの重複を除く
        lectures.joins(:reviews)
                .where(conditions.join(' AND '), *params_values)
                .distinct
      end

      def count_filtered_lectures_by_review_details
        conditions, params_values = build_review_search_conditions
        return 0 if conditions.empty?

        # 基本クエリを構築
        base_query = Lecture.canonical

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

        review_year = params[:academic_year].presence || params[:period_year].presence
        if review_year
          conditions << '(reviews.academic_year = ? OR (reviews.academic_year IS NULL AND reviews.period_year = ?))'
          params_values << review_year.to_i
          params_values << review_year.to_s
        end

        if params[:review_term_code].present?
          review_term = params[:review_term_code]
          legacy_terms = Review::PERIOD_TERM_TO_CODE.select { |_label, code| code == review_term }.keys
          conditions << '(reviews.term_code = ? OR (reviews.term_code IS NULL AND reviews.period_term IN (?)))'
          params_values << review_term
          params_values << legacy_terms
        elsif params[:period_term].present?
          review_term = Review::PERIOD_TERM_TO_CODE[params[:period_term]]
          if review_term
            legacy_terms = Review::PERIOD_TERM_TO_CODE.select { |_label, code| code == review_term }.keys
            conditions << '(reviews.term_code = ? OR (reviews.term_code IS NULL AND reviews.period_term IN (?)))'
            params_values << review_term
            params_values << legacy_terms
          else
            conditions << 'reviews.period_term = ?'
            params_values << params[:period_term]
          end
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
