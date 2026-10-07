# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Syllabus::ScheduleParser do
  it '複数曜限をregularとして解析すること' do
    result = described_class.call('月２|木 2', term_code: 'A')

    expect(result.kind).to eq('regular')
    expect(result.slots).to contain_exactly([1, 2], [4, 2])
    expect(result.error).to be_nil
  end

  it '集中・他・未知値を区別すること' do
    expect(described_class.call('', term_code: '4').kind).to eq('intensive')
    expect(described_class.call('他', term_code: 'A').kind).to eq('other')
    expect(described_class.call('曜日未定', term_code: 'A')).to have_attributes(kind: 'unknown', error: be_present)
  end
end
