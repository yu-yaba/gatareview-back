# frozen_string_literal: true

module Api
  module V1
    class MypageController < ApplicationController
      include Authenticatable

      def show
        # ユーザーの基本情報
        user_info = {
          id: current_user.id,
          name: current_user.name,
          email: current_user.email,
          avatar_url: current_user.avatar_url,
          provider: current_user.provider
        }

        # 統計情報の計算
        statistics = calculate_statistics

        # ブックマークした授業一覧
        bookmarked_lectures = fetch_bookmarked_lectures

        # ユーザーのレビュー一覧
        user_reviews = fetch_user_reviews

        # レビュー数ランキングでの順位
        ranking_position = calculate_ranking_position

        render json: {
          user: user_info,
          statistics: statistics,
          bookmarked_lectures: bookmarked_lectures,
          user_reviews: user_reviews,
          ranking_position: ranking_position
        }
      end

      def reviews
        page = params[:page]&.to_i || 1
        per_page = params[:per_page]&.to_i || 10
        per_page = [per_page, 50].min # 最大50件まで制限
        
        # ユーザーのレビュー一覧をページネーション付きで取得
        reviews = current_user.reviews
                             .includes(:lecture)
                             .order(created_at: :desc)
                             .offset((page - 1) * per_page)
                             .limit(per_page)
        
        # 総レビュー数
        total_count = current_user.reviews.count
        total_pages = (total_count.to_f / per_page).ceil
        
        # レビューデータの整形
        reviews_data = reviews.map do |review|
          {
            id: review.id,
            rating: review.rating,
            content: review.content,
            created_at: review.created_at,
            thanks_count: review.thanks_count || 0,
            textbook: review.textbook,
            attendance: review.attendance,
            grading_type: review.grading_type,
            content_difficulty: review.content_difficulty,
            content_quality: review.content_quality,
            period_year: review.period_year,
            period_term: review.period_term,
            user_id: review.user_id,
            lecture: {
              id: review.lecture.id,
              title: review.lecture.title,
              lecturer: review.lecture.lecturer,
              faculty: review.lecture.faculty
            }
          }
        end
        
        # 統計情報
        statistics = {
          total_reviews: total_count,
          average_rating: current_user.reviews.average(:rating)&.round(1) || 0.0
        }
        
        render json: {
          reviews: reviews_data,
          pagination: {
            current_page: page,
            total_pages: total_pages,
            total_count: total_count,
            per_page: per_page
          },
          statistics: statistics
        }
      end

      def bookmarks
        page = params[:page]&.to_i || 1
        per_page = params[:per_page]&.to_i || 10
        per_page = [per_page, 50].min # 最大50件まで制限
        
        # N+1クエリ問題を解決: レビュー数と平均評価を一括取得
        bookmarks = current_user.bookmarks
                               .joins(:lecture)
                               .left_joins(lecture: :reviews)
                               .select(
                                 'bookmarks.*',
                                 'lectures.id as lecture_id',
                                 'lectures.title',
                                 'lectures.lecturer',
                                 'lectures.faculty',
                                 'COUNT(reviews.id) as review_count',
                                 'ROUND(AVG(reviews.rating), 1) as avg_rating'
                               )
                               .group('bookmarks.id', 'lectures.id')
                               .order('bookmarks.created_at DESC')
                               .offset((page - 1) * per_page)
                               .limit(per_page)
        
        # 総ブックマーク数
        total_count = current_user.bookmarks.count
        total_pages = (total_count.to_f / per_page).ceil
        
        # ブックマークデータの整形
        bookmarks_data = bookmarks.map do |bookmark|
          {
            id: bookmark.lecture_id,
            title: bookmark.title,
            lecturer: bookmark.lecturer,
            faculty: bookmark.faculty,
            bookmarked_at: bookmark.created_at,
            review_count: bookmark.review_count.to_i,
            avg_rating: bookmark.avg_rating&.to_f || 0.0
          }
        end
        
        # 統計情報
        statistics = {
          total_bookmarks: total_count
        }
        
        render json: {
          bookmarks: bookmarks_data,
          pagination: {
            current_page: page,
            total_pages: total_pages,
            total_count: total_count,
            per_page: per_page
          },
          statistics: statistics
        }
      end

      private

      def calculate_statistics
        # 投稿したレビュー数
        reviews_count = current_user.reviews.count
        
        # もらったありがとうの総数
        total_thanks = Thank.joins(:review)
                           .where(reviews: { user_id: current_user.id })
                           .count
        
        # 最新のレビュー
        latest_review = current_user.reviews
                                   .includes(:lecture)
                                   .order(created_at: :desc)
                                   .first

        {
          reviews_count: reviews_count,
          total_thanks_received: total_thanks,
          latest_review: latest_review&.as_json(
            include: { lecture: { only: %i[id title lecturer] } },
            only: %i[id rating content created_at]
          )
        }
      end

      def fetch_bookmarked_lectures
        # N+1クエリ問題を解決: レビュー数と平均評価を一括取得
        bookmarks = current_user.bookmarks
                               .joins(:lecture)
                               .left_joins(lecture: :reviews)
                               .select(
                                 'bookmarks.*',
                                 'lectures.id as lecture_id',
                                 'lectures.title',
                                 'lectures.lecturer',
                                 'lectures.faculty',
                                 'COUNT(reviews.id) as review_count',
                                 'ROUND(AVG(reviews.rating), 1) as avg_rating'
                               )
                               .group('bookmarks.id', 'lectures.id')
                               .order('bookmarks.created_at DESC')
                               .limit(10)
        
        bookmarks.map do |bookmark|
          {
            id: bookmark.lecture_id,
            title: bookmark.title,
            lecturer: bookmark.lecturer,
            faculty: bookmark.faculty,
            bookmarked_at: bookmark.created_at,
            # レビュー数と平均評価も含める
            review_count: bookmark.review_count.to_i,
            avg_rating: bookmark.avg_rating&.to_f || 0.0
          }
        end
      end

      def fetch_user_reviews
        current_user.reviews
                   .includes(:lecture)
                   .order(created_at: :desc)
                   .limit(10)
                   .map do |review|
          {
            id: review.id,
            rating: review.rating,
            content: review.content,
            created_at: review.created_at,
            thanks_count: review.thanks_count || 0,
            textbook: review.textbook,
            attendance: review.attendance,
            grading_type: review.grading_type,
            content_difficulty: review.content_difficulty,
            content_quality: review.content_quality,
            period_year: review.period_year,
            period_term: review.period_term,
            user_id: review.user_id,
            lecture: {
              id: review.lecture.id,
              title: review.lecture.title,
              lecturer: review.lecture.lecturer,
              faculty: review.lecture.faculty
            }
          }
        end
      end

      def calculate_ranking_position
        # 全ユーザーのレビュー数でランキング計算
        # 同じレビュー数のユーザーには同じ順位を割り当て
        user_reviews_count = current_user.reviews.count
        
        # 実際のレビュー数に基づいて動的にランキングを計算
        # カウンターキャッシュに依存せず、正確な数値を使用
        users_with_more_reviews = User.joins(:reviews)
                                     .group('users.id')
                                     .having('COUNT(reviews.id) > ?', user_reviews_count)
                                     .count.length
        
        total_users_with_reviews = User.joins(:reviews)
                                      .distinct
                                      .count
        
        {
          position: users_with_more_reviews + 1,
          total_users: total_users_with_reviews,
          user_reviews_count: user_reviews_count
        }
      end
    end
  end
end