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
        
        if @thank&.destroy
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
      # 別の利用者が同じレビューへ同時にありがとうすると thanks_count の更新でデッドロックし得るので1回やり直す。
      def save_thank
        DeadlockRetry.call { @thank.save }
      rescue ActiveRecord::RecordNotUnique
        @thank.errors.add(:base, :already_thanked)
        false
      end

      def set_review
        @review = Review.find(params[:review_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'レビューが見つかりません' }, status: :not_found
      end
    end
  end
end