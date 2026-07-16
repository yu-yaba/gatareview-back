# frozen_string_literal: true

module Syllabus
  class LegacyDataBackfill
    Error = Class.new(StandardError)

    Result = Struct.new(:lectures_updated, :reviews_updated, :offerings_updated, keyword_init: true)

    def initialize(confirm:)
      @confirm = confirm
    end

    def call
      raise Error, 'CONFIRM=true が必要です' unless confirm

      audit = DatabaseAudit.new.call
      blocking = {
        lectures_with_missing_identity: audit.lectures_with_missing_identity,
        normalized_lecture_duplicates: audit.normalized_lecture_duplicates,
        invalid_review_lecture_ids: audit.invalid_review_lecture_ids,
        orphan_review_ids: audit.orphan_review_ids
      }.reject { |_key, value| value.empty? }
      raise Error, "監査エラーがあるためbackfillできません: #{blocking.to_json}" if blocking.any?

      counts_before = review_aggregates
      result = nil
      ApplicationRecord.transaction do
        lectures_updated = backfill_lectures
        reviews_updated = backfill_reviews
        offerings_updated = backfill_offerings
        raise Error, 'Review集計がbackfill前後で一致しません' unless review_aggregates == counts_before

        result = Result.new(lectures_updated:, reviews_updated:, offerings_updated:)
      end
      result
    end

    private

    attr_reader :confirm

    def backfill_lectures
      count = 0
      Lecture.canonical.find_each do |lecture|
        key = Normalizer.lecture_key(title: lecture.title, lecturer: lecture.lecturer, faculty: lecture.faculty)
        next if lecture.normalized_key == key

        lecture.update_columns(normalized_key: key)
        count += 1
      end
      count
    end

    def backfill_reviews
      count = 0
      Review.find_each do |review|
        year = review.period_year.to_s.match?(/\A\d{4}\z/) ? review.period_year.to_i : nil
        term_code = Review::PERIOD_TERM_TO_CODE[review.period_term]
        offering = if year
                     scope = LectureOffering.where(lecture_id: review.lecture_id.to_i, year:)
                     scope = scope.where(term_code:) if term_code
                     scope.one? ? scope.first : nil
                   end

        review.update_columns(
          lecture_id_bigint: review.lecture_id.to_i,
          academic_year: year,
          term_code:,
          lecture_offering_id: offering&.id
        )
        count += 1
      end
      count
    end

    def backfill_offerings
      organizations = SyllabusOrganization.all.group_by(&:code)
      count = 0
      LectureOffering.includes(:lecture, :offering_slots).find_each do |offering|
        organization = organizations.fetch(offering.shozoku_code, []).find do |candidate|
          candidate.valid_from_year <= offering.year && (candidate.valid_until_year.nil? || candidate.valid_until_year >= offering.year)
        end
        slots = offering.offering_slots.sort_by { |slot| [slot.day, slot.period] }
        raw = slots.map { |slot| "#{OfferingSlot::DAYS.key(slot.day)}#{slot.period}" }.join('|')
        schedule_kind = if slots.any?
                          'regular'
                        elsif offering.term_code == '4'
                          'intensive'
                        elsif %w[5 9].include?(offering.term_code)
                          'other'
                        else
                          'unknown'
                        end
        source = {
          title: offering.lecture.title,
          lecturer: offering.lecture.lecturer,
          faculty: offering.lecture.faculty,
          year: offering.year,
          registration_code: offering.registration_code,
          shozoku_code: offering.shozoku_code,
          semester_label: offering.semester_label,
          term_label: offering.term_label,
          term_code: offering.term_code,
          raw_day_periods: raw,
          schedule_kind:,
          slots: slots.map { |slot| [slot.day, slot.period] }
        }
        offering.update_columns(
          syllabus_organization_id: organization&.id,
          source_title: offering.lecture.title,
          source_lecturer: offering.lecture.lecturer,
          source_faculty: offering.lecture.faculty,
          raw_day_periods: raw,
          schedule_kind:,
          source_status: 'active',
          source_checksum: Normalizer.checksum(source)
        )
        count += 1
      end
      count
    end

    def review_aggregates
      {
        count: Review.count,
        by_lecture: Review.group(:lecture_id).count,
        averages: Review.group(:lecture_id).average(:rating).transform_values(&:to_f)
      }
    end
  end
end
