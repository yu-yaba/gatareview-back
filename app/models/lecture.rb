# frozen_string_literal: true

class Lecture < ApplicationRecord
  has_many :reviews
  has_many_attached :images
end
