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

        # レビュー数ランキングでの順位
        ranking_position = calculate_ranking_position

        render json: {
          user: user_info,
          statistics: statistics,
          bookmarked_lectures: bookmarked_lectures,
          ranking_position: ranking_position
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

      def calculate_ranking_position
        # 全ユーザーのレビュー数でランキング計算
        # 同じレビュー数のユーザーには同じ順位を割り当て
        user_reviews_count = current_user.reviews.count
        
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