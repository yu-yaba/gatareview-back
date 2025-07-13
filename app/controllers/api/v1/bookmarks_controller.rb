# frozen_string_literal: true

module Api
  module V1
    class BookmarksController < ApplicationController
      include Authenticatable
      before_action :set_lecture

      def create
        @bookmark = @lecture.bookmarks.build(user: current_user)
        
        if @bookmark.save
          render json: { 
            success: true, 
            message: 'ブックマークに追加しました'
          }, status: :created
        else
          render json: { 
            success: false, 
            errors: @bookmark.errors.full_messages 
          }, status: :unprocessable_entity
        end
      end

      def destroy
        @bookmark = @lecture.bookmarks.find_by(user: current_user)
        
        if @bookmark&.destroy
          render json: { 
            success: true, 
            message: 'ブックマークを削除しました'
          }
        else
          render json: { 
            success: false, 
            message: 'ブックマークが見つかりません' 
          }, status: :not_found
        end
      end

      def show
        # 現在のユーザーがこの授業をブックマークしているかチェック
        @bookmark = @lecture.bookmarks.find_by(user: current_user)
        
        render json: {
          bookmarked: @bookmark.present?
        }
      end

      private

      def set_lecture
        @lecture = Lecture.find(params[:lecture_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: '授業が見つかりません' }, status: :not_found
      end
    end
  end
end