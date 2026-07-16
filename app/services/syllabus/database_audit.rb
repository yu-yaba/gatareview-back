# frozen_string_literal: true

require 'set'

module Syllabus
  class DatabaseAudit
    Result = Struct.new(
      :lecture_count,
      :review_count,
      :bookmark_count,
      :timetable_entry_count,
      :lectures_with_missing_identity,
      :normalized_lecture_duplicates,
      :invalid_review_lecture_ids,
      :orphan_review_ids,
      :orphan_bookmark_ids,
      :orphan_timetable_entry_ids,
      :orphan_offering_ids,
      :duplicate_user_review_keys,
      :offering_counts,
      keyword_init: true
    )

    def call
      lecture_ids = Lecture.pluck(:id).to_set
      normalized_groups = Lecture.where(merged_into_lecture_id: nil).group_by do |lecture|
        lecture.normalized_key.presence || Normalizer.lecture_key(title: lecture.title, lecturer: lecture.lecturer, faculty: lecture.faculty)
      end
      invalid_review_ids = []
      orphan_review_ids = []
      Review.find_each do |review|
        if !review.lecture_id.to_s.match?(/\A\d+\z/)
          invalid_review_ids << review.id
        elsif !lecture_ids.include?(review.lecture_id.to_i)
          orphan_review_ids << review.id
        end
      end

      Result.new(
        lecture_count: Lecture.count,
        review_count: Review.count,
        bookmark_count: Bookmark.count,
        timetable_entry_count: timetable_available? ? TimetableEntry.count : 0,
        lectures_with_missing_identity: Lecture.where(title: [nil, '']).or(Lecture.where(lecturer: [nil, ''])).or(Lecture.where(faculty: [nil, ''])).pluck(:id),
        normalized_lecture_duplicates: normalized_groups.filter_map { |key, lectures| [key, lectures.map(&:id)] if lectures.many? }.to_h,
        invalid_review_lecture_ids: invalid_review_ids,
        orphan_review_ids: orphan_review_ids,
        orphan_bookmark_ids: Bookmark.where.not(lecture_id: lecture_ids.to_a).pluck(:id),
        orphan_timetable_entry_ids: timetable_available? ? TimetableEntry.where.not(lecture_id: lecture_ids.to_a).pluck(:id) : [],
        orphan_offering_ids: LectureOffering.where.not(lecture_id: lecture_ids.to_a).pluck(:id),
        duplicate_user_review_keys: Review.where.not(user_id: nil).group(:user_id, :lecture_id).having('COUNT(*) > 1').count,
        offering_counts: LectureOffering.group(:year, :source_status).count
      )
    end

    private

    def timetable_available?
      defined?(TimetableEntry) && TimetableEntry.table_exists?
    end
  end
end
