# frozen_string_literal: true

module Syllabus
  module DomainReferenceIntegrity
    module_function

    def valid_for_offerings?(offering_ids)
      LectureOffering.where(id: Array(offering_ids).compact.uniq).find_each.all? do |offering|
        reviews_match?(offering) && timetable_entries_match?(offering)
      end
    end

    def reviews_match?(offering)
      Review.where(lecture_offering_id: offering.id)
            .pluck(:lecture_id, :academic_year, :term_code)
            .all? do |lecture_id, academic_year, term_code|
        lecture_id.to_s == offering.lecture_id.to_s &&
          (academic_year.nil? || academic_year == offering.year) &&
          (term_code.nil? || term_code == offering.term_code)
      end
    end

    def timetable_entries_match?(offering)
      return true unless defined?(TimetableEntry) && TimetableEntry.table_exists?

      TimetableEntry.where(lecture_offering_id: offering.id)
                    .pluck(:lecture_id, :year)
                    .all? { |lecture_id, year| lecture_id == offering.lecture_id && year == offering.year }
    end

    private_class_method :reviews_match?, :timetable_entries_match?
  end
end
