# frozen_string_literal: true

module Api
  module V1
    class TimetablesController < ApplicationController
      include Authenticatable

      def show
        today = current_japan_date
        year = valid_year(params[:year]) || current_academic_year(today)
        term = valid_term(params[:term]) || current_term(today)
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

        replace = ActiveModel::Type::Boolean.new.cast(params[:replace])
        expected_conflict_ids = normalized_conflict_ids
        conflicts_for_response = nil
        conflict_state_changed = false
        offering_invalid = false
        offering = nil
        entries = nil

        TimetableEntry.transaction do
          # 同一ユーザーの空きセルへの同時追加も直列化する。
          # timetable_entriesの行ロックだけでは、まだ行がないセルを保護できない。
          current_user.lock!
          # import側と同じLecture -> Offering順でロックし、循環待ちを避ける。
          lecture.lock!
          offering = resolve_offering(lecture, year, lock: true)
          if params[:lecture_offering_id].present? && offering.nil?
            offering_invalid = true
            raise ActiveRecord::Rollback
          end

          conflicts = slot_conflicts(year, placements, lock: true)
          current_conflict_ids = conflicts.map(&:id).sort

          if replace
            unless expected_conflict_ids == current_conflict_ids
              conflicts_for_response = conflicts
              conflict_state_changed = true
              raise ActiveRecord::Rollback
            end
          elsif conflicts.any?
            conflicts_for_response = conflicts
            raise ActiveRecord::Rollback
          end

          conflicts.each(&:destroy!) if conflicts.any?
          entries = placements.map do |placement|
            current_user.timetable_entries.create!(lecture: lecture, lecture_offering: offering, year: year, **placement)
          end
        end

        if offering_invalid
          return render json: { success: false, errors: ['開講情報が講義または年度と一致しません'] }, status: :unprocessable_entity
        end
        if conflicts_for_response
          return render_conflicts(conflicts_for_response, state_changed: conflict_state_changed)
        end

        render json: { success: true, message: '時間割に追加しました', entries: serialize_entries(entries) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        conflicts = slot_conflicts(year, placements)
        return render_conflicts(conflicts, state_changed: true) if conflicts.any?

        render json: { success: false, errors: [e.record.errors.full_messages.to_sentence] }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotUnique
        # user行ロックを通らない別経路から同時書き込みされても500にしない。
        render_conflicts(slot_conflicts(year, placements), state_changed: true)
      end

      def destroy
        entry = nil
        TimetableEntry.transaction do
          current_user.lock!
          entry = current_user.timetable_entries.lock.find_by(id: params[:id])
          next unless entry

          if ActiveModel::Type::Boolean.new.cast(params[:all_for_lecture])
            current_user.timetable_entries.where(lecture_id: entry.lecture_id, year: entry.year).destroy_all
          else
            entry.destroy!
          end
        end

        return render json: { success: false, message: '時間割の講義が見つかりません' }, status: :not_found unless entry

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
        raw_placements = params[:placements]
        return [] unless raw_placements.is_a?(Array) && raw_placements.any?

        placements = raw_placements.map do |placement|
          next unless placement.is_a?(ActionController::Parameters) || placement.is_a?(Hash)

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
        end

        return [] if placements.any?(&:nil?)

        placements.uniq
      end

      def slot_conflicts(year, placements, lock: false)
        scope = current_user.timetable_entries
        scope = scope.lock if lock

        placements.filter_map do |placement|
          next if placement[:term].zero?

          scope.find_by(year: year, term: placement[:term], day: placement[:day], period: placement[:period])
        end
      end

      def resolve_offering(lecture, year, lock: false)
        return nil unless params[:lecture_offering_id].present?

        scope = lecture.lecture_offerings.active
        scope = scope.lock if lock
        scope.find_by(id: params[:lecture_offering_id], year:)
      end

      def valid_year(value)
        year = strict_integer(value)
        year&.between?(1000, 9999) ? year : nil
      end

      def valid_term(value)
        term = strict_integer(value)
        term&.between?(0, 4) ? term : nil
      end

      def valid_slot(value)
        slot = strict_integer(value)
        slot&.between?(1, 7) ? slot : nil
      end

      def strict_integer(value)
        return value if value.is_a?(Integer)
        return unless value.is_a?(String) && value.match?(/\A-?\d+\z/)

        Integer(value, 10)
      rescue ArgumentError
        nil
      end

      def normalized_conflict_ids
        values = params[:conflict_ids]
        return nil unless values.is_a?(Array)

        ids = values.map do |value|
          id = strict_integer(value)
          break unless id&.positive?

          id
        end
        return nil unless ids.is_a?(Array) && ids.length == values.length && ids.uniq.length == ids.length

        ids.sort
      end

      def render_conflicts(conflicts, state_changed:)
        message = if state_changed
                    '時間割の状態が変更されました。内容を確認して再度追加してください'
                  else
                    '既に登録済みのコマがあります'
                  end

        render json: {
          success: false,
          message: message,
          errors: [message],
          conflict_state_changed: state_changed,
          conflicts: serialize_entries(conflicts)
        }, status: :conflict
      end

      def current_japan_date
        Time.current.in_time_zone('Asia/Tokyo').to_date
      end

      def current_academic_year(date)
        date.month >= 4 ? date.year : date.year - 1
      end

      def current_term(date)
        case date.month
        when 4, 5 then 1
        when 6, 7, 8 then 2
        when 9, 10, 11 then 3
        else 4
        end
      end
    end
  end
end
