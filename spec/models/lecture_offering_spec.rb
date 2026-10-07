# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LectureOffering do
  subject(:offering) do
    described_class.new(
      lecture: FactoryBot.create(:lecture),
      year: 2026,
      registration_code: '261H2001',
      shozoku_code: '01',
      term_code: term_code
    )
  end

  let(:term_code) { 'E' }

  it 'builds the official syllabus URL' do
    expect(offering.syllabus_url).to eq('https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/01/01_261H2001_ja_JP.html')
  end

  it 'expands term codes and identifies intensive offerings' do
    expect(offering.term_numbers).to eq([1, 2])
    expect(offering).not_to be_intensive

    offering.term_code = '4'
    expect(offering.term_numbers).to eq([])
    expect(offering).to be_intensive
  end

  it 'unknown schedule is not treated as intensive' do
    offering.term_code = nil
    offering.schedule_kind = 'unknown'

    expect(offering).not_to be_intensive
  end

  it 'requires a year, registration code, and shozoku code' do
    offering.year = nil
    offering.registration_code = nil
    offering.shozoku_code = nil

    expect(offering).not_to be_valid
    expect(offering.errors.attribute_names).to include(:year, :registration_code, :shozoku_code)
  end

  it 'normalizes term labels before looking up their code' do
    expect(described_class.term_code_for(' 第1，2ターム ')).to eq('E')
    expect(described_class.term_code_for('第1～3ターム')).to eq('H')
  end
end
