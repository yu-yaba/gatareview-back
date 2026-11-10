# frozen_string_literal: true

module Api
  module V1
    class ThanksController < ApplicationController
      include Authenticatable
      before_action :set_review

      def create
        @thank = @review.thanks.build(user: current_user)
        
        if save_thank
          render json: { 
            success: true, 
            message: 'ありがとうを送信しました',
            thanks_count: @review.reload.thanks_count
          }, status: :created
        else
          render json: { 
            success: false, 
            errors: @thank.errors.full_messages 
          }, status: :unprocessable_entity
        end
      end

      def destroy
        @thank = @review.thanks.find_by(user: current_user)
        
        if @thank && with_locked_review { @thank.destroy }
          render json: { 
            success: true, 
            message: 'ありがとうを取り消しました',
            thanks_count: @review.reload.thanks_count
          }
        else
          render json: { 
            success: false, 
            message: 'ありがとうが見つかりません' 
          }, status: :not_found
        end
      end

      def show
        # 現在のユーザーがこのレビューにありがとうを送っているかチェック
        @thank = @review.thanks.find_by(user: current_user)
        
        render json: {
          thanked: @thank.present?,
          thanks_count: @review.thanks_count
        }
      end

      private

      # 連打などで同時に届いた2件目は、DB の一意インデックスで止まる。検証と同じ文言で 422 を返す。
      def save_thank
        with_locked_review { @thank.save }
      rescue ActiveRecord::RecordNotUnique
        @thank.errors.add(:base, :already_thanked)
        false
      end

      # 同じレビューへのありがとうの追加・取り消しは、レビューの行をロックしてから行う。
      # 別々の利用者の thanks_count の更新どうしがデッドロックしないよう1件ずつ処理する。
      # ロックするときに件数を読み直すので、まれにデッドロックでやり直しても二重に数えない。
      def with_locked_review
        DeadlockRetry.call do
          Thank.transaction do
            # 失敗した試行で上がったままの件数を捨て、ロックしてから DB の値を読み直す
            @review.reload(lock: true)
            yield
          end
        end
      end

      def set_review
        @review = Review.find(params[:review_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'レビューが見つかりません' }, status: :not_found
      end
    end
  end
end