# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Lecture, type: :model do
  it 'raw表記が異なっても同じnormalized_keyをDB unique制約で拒否すること' do
    first = FactoryBot.create(
      :lecture,
      title: '心理学概論A',
      lecturer: '山田 太郎',
      faculty: 'H:人文学部'
    )
    duplicate = FactoryBot.build(
      :lecture,
      title: '心理学概論Ａ',
      lecturer: '山田太郎',
      faculty: 'H:人文学部'
    )
    duplicate.normalized_key = first.normalized_key

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(Lecture.where(normalized_key: first.normalized_key).count).to eq(1)
  end
end
