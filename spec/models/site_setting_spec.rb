# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SiteSetting, type: :model do
  describe '.current' do
    it 'レコードがない場合は制限OFFの新規設定を返すこと' do
      setting = described_class.current

      expect(setting).to be_new_record
      expect(setting.id).to eq(1)
      expect(setting.lecture_review_restriction_enabled).to eq(false)
    end
  end

  describe '.current!' do
    it '常に同じ1件の設定を返すこと' do
      first = described_class.current!
      second = described_class.current!

      expect(first.id).to eq(1)
      expect(second.id).to eq(1)
      expect(described_class.count).to eq(1)
    end
  end

  describe 'before_validation' do
    it '新規作成時に singleton id を自動で設定すること' do
      site_setting = described_class.create!(lecture_review_restriction_enabled: true)

      expect(site_setting.id).to eq(1)
    end
  end
end
