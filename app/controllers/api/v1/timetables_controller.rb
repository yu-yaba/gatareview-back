# frozen_string_literal: true

module Api
  module V1
    class TimetablesController < ApplicationController
      include Authenticatable

      def show
        year = valid_year(params[:year]) || Date.current.year
        term = valid_term(params[:term]) || current_term
        entries = current_user.timetable_entries.where(year: year).includes(:lecture, :lecture_offering)

        render json: {
          year: year,
          term: term,
          entries: serialize_entries(entries.where(term: term)),
          intensive_entries: serialize_entries(entries.where(term: 0)),
          available_terms: entries.where(term: 1..4).distinct.order(:term).pluck(:term),
          available_years: current_user.timetable_entries.distinct.order(year: :desc).pluck(:year)
        }
      end

      def create
        lecture = Lecture.find_by(id: params[:lecture_id])
        return render json: { success: false, errors: ['講義が見つかりません'] }, status: :not_found unless lecture

        year = valid_year(params[:year])
        placements = normalized_placements
        return render json: { success: false, errors: ['年度または配置内容が不正です'] }, status: :unprocessable_entity if year.nil? || placements.empty?

        offering = resolve_offering(lecture, year)
        if params[:lecture_offering_id].present? && offering.nil?
          return render json: { success: false, errors: ['開講情報が講義または年度と一致しません'] }, status: :unprocessable_entity
        end

        conflicts = slot_conflicts(year, placements)
        if conflicts.any? && !ActiveModel::Type::Boolean.new.cast(params[:replace])
          return render json: { success: false, message: '既に登録済みのコマがあります', conflicts: serialize_entries(conflicts) }, status: :conflict
        end

        entries = TimetableEntry.transaction do
          conflicts.each(&:destroy!) if conflicts.any?
          placements.map do |placement|
            current_user.timetable_entries.create!(lecture: lecture, lecture_offering: offering, year: year, **placement)
          end
        end

        render json: { success: true, message: '時間割に追加しました', entries: serialize_entries(entries) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { success: false, errors: [e.record.errors.full_messages.to_sentence] }, status: :unprocessable_entity
      end

      def destroy
        entry = current_user.timetable_entries.find_by(id: params[:id])
        return render json: { success: false, message: '時間割の講義が見つかりません' }, status: :not_found unless entry

        if ActiveModel::Type::Boolean.new.cast(params[:all_for_lecture])
          current_user.timetable_entries.where(lecture_id: entry.lecture_id, year: entry.year).destroy_all
        else
          entry.destroy!
        end

        render json: { success: true, message: '時間割から削除しました' }
      end

      private

      def serialize_entries(entries)
        records = entries.to_a
        lecture_ids = records.map(&:lecture_id)
        ratings = Review.where(lecture_id: lecture_ids).group(:lecture_id).average(:rating)
        counts = Review.where(lecture_id: lecture_ids).group(:lecture_id).count
        reviewed_ids = current_user.reviews.where(lecture_id: lecture_ids).distinct.pluck(:lecture_id).map(&:to_i)

        records.map do |entry|
          {
            id: entry.id,
            year: entry.year,
            term: entry.term,
            day: entry.day,
            period: entry.period,
            lecture_offering_id: entry.lecture_offering_id,
            lecture_offering_status: entry.lecture_offering&.source_status,
            lecture: {
              id: entry.lecture.id,
              title: entry.lecture.title,
              lecturer: entry.lecture.lecturer,
              avg_rating: (ratings[entry.lecture_id] || ratings[entry.lecture_id.to_s] || 0).round(1),
              review_count: counts[entry.lecture_id] || counts[entry.lecture_id.to_s] || 0,
              reviewed_by_me: reviewed_ids.include?(entry.lecture_id)
            }
          }
        end
      end

      def normalized_placements
        Array(params[:placements]).filter_map do |placement|
          term = valid_term(placement[:term] || placement['term'])
          next if term.nil?

          if term.zero?
            { term: 0, day: nil, period: nil }
          else
            day = valid_slot(placement[:day] || placement['day'])
            period = valid_slot(placement[:period] || placement['period'])
            next if day.nil? || period.nil?

            { term: term, day: day, period: period }
          end
        end.uniq
      end

      def slot_conflicts(year, placements)
        placements.filter_map do |placement|
          next if placement[:term].zero?

          current_user.timetable_entries.find_by(year: year, term: placement[:term], day: placement[:day], period: placement[:period])
        end
      end

      def resolve_offering(lecture, year)
        return nil unless params[:lecture_offering_id].present?

        lecture.lecture_offerings.active.find_by(id: params[:lecture_offering_id], year:)
      end

      def valid_year(value)
        year = Integer(value, 10)
        year.between?(1000, 9999) ? year : nil
      rescue ArgumentError, TypeError
        nil
      end

      def valid_term(value)
        term = Integer(value, 10)
        term.between?(0, 4) ? term : nil
      rescue ArgumentError, TypeError
        nil
      end

      def valid_slot(value)
        slot = Integer(value, 10)
        slot.between?(1, 7) ? slot : nil
      rescue ArgumentError, TypeError
        nil
      end

      def current_term
        case Date.current.month
        when 4, 5 then 1
        when 6, 7, 8 then 2
        when 9, 10, 11 then 3
        else 4
        end
      end
    end
  end
end
