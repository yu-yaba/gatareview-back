# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Syllabus::Normalizer do
  describe '.lecture_key' do
    it '年度を使わず、全角英数字と教員名の空白を正規化すること' do
      first = described_class.lecture_key(title: '心理学概論Ａ', lecturer: '山田　太郎', faculty: 'H:人文学部')
      second = described_class.lecture_key(title: '心理学概論A', lecturer: '山田太郎', faculty: 'H:人文学部')

      expect(first).to eq(second)
    end
  end
end
