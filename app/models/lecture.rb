# frozen_string_literal: true

class Lecture < ApplicationRecord
  has_many :reviews

  def self.search(faculty, title)
    query_conditions = {}

    query_conditions[:faculty] = params[:faculty] if params
  end
end
