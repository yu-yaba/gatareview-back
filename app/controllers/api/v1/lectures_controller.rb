# frozen_string_literal: true

module Api
  module V1
    class LecturesController < ApplicationController
      include Authenticatable
      skip_before_action :authenticate_request, only: %i[index show popular no_reviews]
      before_action :require_admin_privileges, only: [:create]
      before_action :validate_search_parameters, only: [:index]

      SEARCH_PARAMETERS = %i[
        page search faculty sort period_year period_term textbook attendance grading_type
        content_difficulty content_quality
      ].freeze
      MAX_SEARCH_PARAMETER_LENGTH = 255
      MAX_PAGE = 10_000
      # レビュー詳細条件ごとのSQL断片。値は必ずプレースホルダで渡す。
      REVIEW_FILTER_CONDITIONS = {
        period_year: 'reviews.period_year = ?',
        period_term: 'reviews.period_term = ?',
        textbook: 'reviews.textbook = ?',
        attendance: 'reviews.attendance = ?',
        grading_type: 'reviews.grading_type = ?',
        content_difficulty: 'reviews.content_difficulty = ?',
        content_quality: 'reviews.content_quality = ?'
      }.freeze
      # CSV一括取り込みでは作成日時が同じ授業が大量にあり、評価・件数も同じ値が多い。
      # 同じ値の授業の順序がページ（OFFSET）ごとに変わると重複・欠けが起きるため、
      # どの並び順も最後に一意な lectures.id で順序を確定させる。
      MOST_REVIEWED_ORDER = 'COUNT(reviews.id) DESC, lectures.id DESC'
      SORT_ORDERS = {
        # 評価の高い順（レビューがある授業のみ）
        'highestRating' => 'AVG(reviews.rating) DESC, COUNT(reviews.id) DESC, lectures.id DESC',
        # レビュー数の多い順（レビューがある授業のみ）
        'mostReviewed' => MOST_REVIEWED_ORDER,
        # 最新レビュー順（レビューの最新投稿日時順。レビューがない授業は最後）
        'newest' => 'MAX(reviews.created_at) DESC, lectures.created_at DESC, lectures.id DESC'
      }.freeze
      REVIEWED_ONLY_SORTS = %w[highestRating mostReviewed].freeze

      def index
        page = @requested_page
        per_page = 20

        sort = params[:sort] || 'newest'

        # 基本検索（キーワード、学部）
        lectures = Lecture.all
        lectures = lectures.search_by_title_and_lecturer(params[:search]) if params[:search].present?
        lectures = lectures.where(faculty: params[:faculty]) if params[:faculty].present?

        # レビュー詳細項目による絞り込み（表示する授業だけを決め、並び順の集計には影響させない）
        reviews = matching_reviews
        lectures = lectures.where(id: reviews.select(:lecture_id)) unless reviews.nil?

        # 件数だけをDB内で集計し、授業ごとの集計結果を転送しない。
        total_count = count_lectures(lectures, sort, review_filtered: !reviews.nil?)

        # ページネーション（limit/offsetを使用）
        offset = (page - 1) * per_page
        @lectures = sort_lectures(lectures, sort).limit(per_page).offset(offset)

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

        unless @lecture
          render json: { error: '指定された講義は存在しません。' }, status: :not_found
          return
        end

        render json: @lecture.as_json_with_reviews
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
                           .order(MOST_REVIEWED_ORDER)
                           .limit(4)

        render json: { lectures: Lecture.as_json_reviews(@lectures) }
      end

      def no_reviews
        lectures_without_reviews = Lecture.left_joins(:reviews)
                                          .where(reviews: { id: nil })

        limit = 4
        lectures_count = lectures_without_reviews.count
        max_offset = [lectures_count - limit, 0].max
        offset = max_offset.positive? ? SecureRandom.random_number(max_offset + 1) : 0

        @lectures = lectures_without_reviews.order(:id)
                                            .offset(offset)
                                            .limit(limit)

        render json: { lectures: Lecture.as_json_reviews(@lectures) }
      end

      private

      def validate_search_parameters
        invalid = SEARCH_PARAMETERS.any? do |name|
          value = params[name]
          !value.nil? && (!value.is_a?(String) || value.length > MAX_SEARCH_PARAMETER_LENGTH)
        end
        return render_invalid_search if invalid

        @requested_page = params[:page].blank? ? 1 : [Integer(params[:page], 10), 1].max
        render_invalid_search if @requested_page > MAX_PAGE
      rescue ArgumentError, TypeError
        render_invalid_search
      end

      def render_invalid_search
        render json: { error: '検索条件の形式または長さが不正です。' }, status: :bad_request
      end

      def lecture_params
        params.expect(lecture: %i[title lecturer faculty])
      end

      def require_admin_privileges
        unless current_user&.admin?
          render json: { error: '管理者権限が必要です' }, status: :forbidden
          return
        end
      end

      def sort_lectures(lectures, sort)
        case sort
        when *REVIEWED_ONLY_SORTS
          lectures.joins(:reviews).group('lectures.id').order(SORT_ORDERS.fetch(sort))
        when 'newest'
          lectures.left_joins(:reviews).group('lectures.id').order(SORT_ORDERS.fetch(sort))
        else
          lectures.order(:id)
        end
      end

      # 評価順・レビュー数順はレビューがある授業だけが対象。詳細条件で絞り込んだ授業には必ずレビューが
      # あるため、その場合と、それ以外の並び順は並び替え用のJOINなしで数える。
      def count_lectures(lectures, sort, review_filtered:)
        return lectures.joins(:reviews).distinct.count(:id) if REVIEWED_ONLY_SORTS.include?(sort) && !review_filtered

        lectures.count
      end

      # 詳細条件は「条件に合うレビューが1件以上ある授業か」だけを決める（サブクエリで絞り込む）。
      # 並び順の集計（平均評価・件数・最新投稿日時）は、一覧に表示する値と同じく全レビューを対象にする。
      # JOINした reviews 自体を絞ると、並び順だけが条件に合うレビューの集計になり、表示とずれる。
      # 詳細条件が1つもなければ nil を返す。
      def matching_reviews
        filters = REVIEW_FILTER_CONDITIONS.select { |name, _sql| params[name].present? }
        return if filters.empty?

        filters.reduce(Review.all) { |scope, (name, sql)| scope.where(sql, params[name]) }
      end
    end
  end
end
