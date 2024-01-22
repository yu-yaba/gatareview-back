# frozen_string_literal: true

class Lecture < ApplicationRecord
  has_many :reviews
  validates :title, :lecturer, :faculty, presence: true
  validates :title, uniqueness: { scope: [:lecturer, :faculty] }
end
