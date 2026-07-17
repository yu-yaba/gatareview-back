# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Syllabus::OfferingSnapshot do
  def captured_sql
    statements = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      statements << payload[:sql] unless payload[:name] == 'SCHEMA'
    end

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') { yield }
    statements
  end

  it '照合時はSlotが0件でもlecture_offering_id範囲をFOR UPDATEでlockすること' do
    lecture = FactoryBot.create(:lecture)
    offering = LectureOffering.create!(
      lecture:,
      year: 2027,
      registration_code: '271H2001',
      shozoku_code: '01',
      term_code: 'A'
    )
    expected = described_class.capture(offering)
    statements = captured_sql do
      LectureOffering.transaction(requires_new: true) do
        locked_offering = LectureOffering.lock.find(offering.id)
        expect(described_class.matches_for_update?(locked_offering, expected)).to be(true)
      end
    end

    slot_lock_sql = statements.find do |sql|
      sql.include?('FROM `offering_slots`') && sql.include?('FOR UPDATE')
    end
    expect(slot_lock_sql).to include('`offering_slots`.`lecture_offering_id` =')
  end

  it '解析用のcaptureはSlotをlockしないこと' do
    lecture = FactoryBot.create(:lecture)
    offering = LectureOffering.create!(
      lecture:,
      year: 2027,
      registration_code: '271H2002',
      shozoku_code: '01',
      term_code: 'A'
    )

    statements = captured_sql { described_class.capture(offering) }
    slot_sql = statements.select { |sql| sql.include?('FROM `offering_slots`') }

    expect(slot_sql).not_to be_empty
    expect(slot_sql).to all(satisfy { |sql| !sql.include?('FOR UPDATE') })
  end
end
