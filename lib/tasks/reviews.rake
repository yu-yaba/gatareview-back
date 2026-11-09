# frozen_string_literal: true

require 'digest'

namespace :reviews do
  desc '同じ利用者・同じ授業のレビュー重複を一覧表示する（読み取りのみ。重複があれば終了コード1）'
  task duplicates: :environment do
    groups = Review.where.not(user_id: nil)
                   .group(:user_id, :lecture_id)
                   .having('COUNT(*) > 1')
                   .order(:user_id, :lecture_id)
                   .count

    if groups.empty?
      puts '重複はありません。一意インデックスの migration を実行できます。'
      next
    end

    puts "同じ利用者・同じ授業のレビューが #{groups.size} 組あります。データは変更していません。"
    puts '本文は表示しません。本文ハッシュが同じものは同じ内容の再送です。'
    groups.each do |(user_id, lecture_id), count|
      puts
      puts "user_id=#{user_id} lecture_id=#{lecture_id} 件数=#{count}"
      Review.where(user_id: user_id, lecture_id: lecture_id).order(:id).each do |review|
        digest = Digest::SHA256.hexdigest(review.content.to_s)[0, 12]
        puts "  id=#{review.id} created_at=#{review.created_at&.iso8601} updated_at=#{review.updated_at&.iso8601} " \
             "rating=#{review.rating} 本文=#{review.content.to_s.length}文字 本文ハッシュ=#{digest} " \
             "thanks=#{review.thanks_count.to_i}"
      end
    end
    exit 1
  end
end
