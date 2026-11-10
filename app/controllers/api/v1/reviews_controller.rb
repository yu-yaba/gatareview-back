# frozen_string_literal: true

module Api
  module V1
    class ReviewsController < ApplicationController
      include Authenticatable

      # created_at / updated_at も返さない。匿名レビューは編集できないため、updated_at が
      # created_at より新しければログイン投稿だと分かり、編集・投稿時刻で同じ人のレビューを
      # 名寄せできてしまう。並び順はサーバー側で決めて配列の順で返す。
      PUBLIC_REVIEW_ATTRIBUTES = %i[
        id rating content lecture_id textbook attendance grading_type content_difficulty content_quality
        period_year period_term
      ].freeze

      skip_before_action :authenticate_request, only: %i[index create total latest]
      before_action :authenticate_optional, only: %i[index]
      before_action :authenticate_optional_for_create, only: [:create]
      before_action :set_lecture, except: %i[total latest update destroy]

      def create
        review_attributes = review_params
        unless recaptcha_verified?
          render json: { success: false, message: 'reCAPTCHA認証に失敗しました' }, status: :unprocessable_entity
          return
        end

        result = ReviewSubmission.new(lecture: @lecture, user: current_user, attributes: review_attributes).call
        @review = result.review

        if result.status == :invalid
          render json: { success: false, errors: @review.errors.full_messages }, status: :unprocessable_entity
        else
          # 再送（同じ内容の投稿のやり直し）は新しく作らずに既存のレビューを返す
          render json: { success: true, review: public_review_json(@review) },
                 status: result.status == :created ? :created : :ok
        end
      end

      def index
        # 同じ投稿時刻のレビューがあっても先頭（全文表示する1件）が変わらないよう id でも並べる
        reviews = @lecture.reviews.order(created_at: :asc, id: :asc)
        access = review_access_state

        reviews_json = reviews.each_with_index.map do |review, index|
          review_data = public_review_json(review)

          unless access[:access_granted]
            # 権限がない場合でも、最初に投稿されたレビュー（一覧の先頭）は全文表示する
            unless index.zero?
              # それ以外のコメントは先頭30文字のみ返す（フロントでぼかし表示）
              review_data['content'] = mask_review_content(review.content) if review.content.present?
            end
          end

          review_data
        end

        render json: {
          reviews: reviews_json,
          access: access
        }
      end

      def total
        total_reviews = Review.count
        render json: { count: total_reviews }
      end

      def update
        @review = Review.find(params[:id])
        
        # 投稿者本人かチェック
        unless @review.user == current_user
          render json: { error: '他のユーザーのレビューは編集できません' }, status: :forbidden
          return
        end
        
        review_attributes = review_params

        if DeadlockRetry.call { @review.update(review_attributes) }
          render json: {
            success: true,
            review: public_review_json(@review)
          }
        else
          render json: { success: false, errors: @review.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @review = Review.find(params[:id])
        
        # 投稿者本人かチェック
        unless @review.user == current_user
          render json: { error: '他のユーザーのレビューは削除できません' }, status: :forbidden
          return
        end
        
        # ありがとうの追加・取り消しと同じくレビューの行をロックしてから消す。
        # 処理中のありがとうを待ってから関連ごと消すので、外部キー違反で失敗しない。
        # 同じ利用者の別のありがとうと重なるとデッドロックし得るので1回やり直す。
        # 失敗した試行の状態を持ち越さないよう、試行ごとにロックして読み直したレコードを消す。
        if DeadlockRetry.call { Review.transaction { Review.lock.find(@review.id).destroy } }
          render json: { success: true, message: 'レビューを削除しました' }
        else
          render json: { success: false, message: 'レビューの削除に失敗しました' }, status: :unprocessable_entity
        end
      end

      def latest
        @reviews = Review.includes(:lecture).order(created_at: :desc, id: :desc).limit(4)
        if @reviews.any?
          reviews_json = @reviews.map do |review|
            review_data = review.as_json(only: %i[id rating])
            # ルートの最新レビューはログイン有無に関わらず全文を返す
            review_data['content'] = review.content
            review_data['lecture'] = review.lecture.as_json(only: %i[id title lecturer faculty])
            review_data
          end
          render json: reviews_json
        else
          render json: { error: 'レビューが見つかりません。' }, status: :not_found
        end
      end

      private

      def set_lecture
        @lecture = Lecture.find(params[:lecture_id])
      end

      # 画面に投稿者を表示しないため、投稿者を特定・名寄せできる値（user / user_id、
      # Google の表示名・プロフィール画像）は公開レスポンスに含めない。
      # 列を追加しても自動で公開されないよう、返す属性は許可リストで固定する。
      def public_review_json(review)
        review.as_json(only: PUBLIC_REVIEW_ATTRIBUTES).merge(
          'thanks_count' => review.thanks_count || 0,
          'is_own' => own_review?(review)
        )
      end

      def own_review?(review)
        current_user.present? && review.user_id.present? && review.user_id == current_user.id
      end

      def review_params
        params.expect(review: %i[rating content period_year period_term textbook attendance grading_type
                                 content_difficulty content_quality])
      end
      
      def recaptcha_verified?
        # テスト環境は外部通信しない
        return true if Rails.env.test?

        # 本番環境では必須。開発環境は未設定でも動作できるようにスキップ可能にする。
        if ENV['RECAPTCHA_SECRET_KEY'].blank?
          Rails.logger.error('RECAPTCHA_SECRET_KEY is not set') if Rails.env.production?
          return !Rails.env.production?
        end
        
        return false if params[:token].blank?

        verifier = RecaptchaVerifier.new(params[:token], 'submit', 0.5, remote_ip: RateLimitDiscriminator.client_ip(request))
        verifier.verify
      end

      # レビュー閲覧権限をチェック
      def has_review_access?(restriction_enabled:)
        return true unless restriction_enabled
        return false unless current_user

        current_user.reviews_count >= 1
      end

      def review_access_state
        restriction_enabled = review_restriction_enabled?
        {
          restriction_enabled: restriction_enabled,
          access_granted: has_review_access?(restriction_enabled: restriction_enabled)
        }
      end

      def review_restriction_enabled?
        SiteSetting.current.lecture_review_restriction_enabled
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.error("Failed to load review restriction setting: #{e.class}")
        true
      end

      # レビューコンテンツを部分的にマスク
      def mask_review_content(content)
        return nil if content.blank?

        content[0, 30]
      end

    end
  end
end
