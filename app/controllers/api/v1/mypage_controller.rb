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
        
        # ユーザーのブックマーク一覧をページネーション付きで取得
        bookmarks = current_user.bookmarks
                               .includes(:lecture)
                               .order(created_at: :desc)
                               .offset((page - 1) * per_page)
                               .limit(per_page)
        
        # 総ブックマーク数
        total_count = current_user.bookmarks.count
        total_pages = (total_count.to_f / per_page).ceil
        
        # ブックマークデータの整形
        bookmarks_data = bookmarks.map do |bookmark|
          lecture = bookmark.lecture
          {
            id: lecture.id,
            title: lecture.title,
            lecturer: lecture.lecturer,
            faculty: lecture.faculty,
            bookmarked_at: bookmark.created_at,
            review_count: lecture.reviews.count,
            avg_rating: lecture.reviews.average(:rating)&.round(1) || 0.0
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
        current_user.bookmarks
                   .includes(:lecture)
                   .order(created_at: :desc)
                   .limit(10)
                   .map do |bookmark|
          lecture = bookmark.lecture
          {
            id: lecture.id,
            title: lecture.title,
            lecturer: lecture.lecturer,
            faculty: lecture.faculty,
            bookmarked_at: bookmark.created_at,
            # レビュー数と平均評価も含める
            review_count: lecture.reviews.count,
            avg_rating: lecture.reviews.average(:rating)&.round(1) || 0.0
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
        
        # reviews_countカラムを更新（カウンターキャッシュが無効な場合のため）
        current_user.update_column(:reviews_count, user_reviews_count) if current_user.reviews_count != user_reviews_count
        
        # 自分より多くレビューを投稿しているユーザー数 + 1 = 順位
        higher_ranked_users = User.where('reviews_count > ?', user_reviews_count).count
        
        {
          position: higher_ranked_users + 1,
          total_users: User.where('reviews_count > 0').count,
          user_reviews_count: user_reviews_count
        }
      end
    end
  end
end