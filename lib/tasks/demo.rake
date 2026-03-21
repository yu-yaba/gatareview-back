# frozen_string_literal: true

namespace :demo do
  desc 'review access 確認用のデモデータを投入する'
  task review_access_seed: :environment do
    ActiveRecord::Base.transaction do
      setting = SiteSetting.current!
      setting.update!(lecture_review_restriction_enabled: false, last_updated_by: nil)

      locked_user = User.find_or_create_by!(email: 'demo-review-access-locked@example.com') do |user|
        user.name = 'レビュー未投稿ユーザー'
        user.provider = 'google'
        user.provider_id = 'demo-review-access-locked'
        user.avatar_url = nil
      end

      unlocked_user = User.find_or_create_by!(email: 'demo-review-access-unlocked@example.com') do |user|
        user.name = 'レビュー投稿済みユーザー'
        user.provider = 'google'
        user.provider_id = 'demo-review-access-unlocked'
        user.avatar_url = nil
      end

      helper_user = User.find_or_create_by!(email: 'demo-review-access-helper@example.com') do |user|
        user.name = 'レビュー補助ユーザー'
        user.provider = 'google'
        user.provider_id = 'demo-review-access-helper'
        user.avatar_url = nil
      end

      admin_user = User.find_or_create_by!(email: 'demo-review-access-admin@example.com') do |user|
        user.name = 'レビュー管理者候補'
        user.provider = 'google'
        user.provider_id = 'demo-review-access-admin'
        user.avatar_url = nil
      end

      zero_review_lecture = Lecture.find_or_create_by!(
        title: '確認用: レビュー0件授業',
        lecturer: '確認用教員0',
        faculty: '工学部'
      )

      one_review_lecture = Lecture.find_or_create_by!(
        title: '確認用: レビュー1件授業',
        lecturer: '確認用教員1',
        faculty: '工学部'
      )

      two_review_lecture = Lecture.find_or_create_by!(
        title: '確認用: レビュー2件授業',
        lecturer: '確認用教員2',
        faculty: '工学部'
      )

      Review.find_or_initialize_by(lecture: one_review_lecture, user: unlocked_user).tap do |review|
        review.rating = 5
        review.content = 'レビュー投稿済みユーザーの確認用レビューです。reviews_count が 1 以上になることを確認するための本文です。'
        review.period_year = '2025'
        review.period_term = '1ターム'
        review.save!
      end

      Review.find_or_initialize_by(lecture: two_review_lecture, user: helper_user).tap do |review|
        review.rating = 4
        review.content = '2件授業の1件目レビューです。閲覧制限ON時でも全文表示される想定の本文です。'
        review.period_year = '2025'
        review.period_term = '1ターム'
        review.save!
      end

      Review.find_or_initialize_by(lecture: two_review_lecture, user: admin_user).tap do |review|
        review.rating = 3
        review.content = '2件授業の2件目レビューです。閲覧制限ON時には先頭30文字だけ返ることを確認するための本文です。'
        review.period_year = '2025'
        review.period_term = '2ターム'
        review.save!
      end

      locked_user.reload
      unlocked_user.reload

      puts 'review access demo data has been prepared'
      puts "site_setting: restriction_enabled=#{setting.reload.lecture_review_restriction_enabled}"
      puts "locked_user: email=#{locked_user.email} reviews_count=#{locked_user.reviews_count}"
      puts "unlocked_user: email=#{unlocked_user.email} reviews_count=#{unlocked_user.reviews_count}"
      puts "admin_candidate: email=#{admin_user.email} reviews_count=#{admin_user.reviews_count}"
      puts "lecture_zero_reviews: id=#{zero_review_lecture.id}"
      puts "lecture_one_review: id=#{one_review_lecture.id}"
      puts "lecture_two_reviews: id=#{two_review_lecture.id}"
      puts 'Set ADMIN_EMAILS to a real login email if you want to access /admin/review-access in the browser.'
    end
  end
end
