# frozen_string_literal: true

class Lecture < ApplicationRecord
  has_many :reviews
end
