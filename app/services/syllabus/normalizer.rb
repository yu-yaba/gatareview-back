# frozen_string_literal: true

require 'digest'

module Syllabus
  module Normalizer
    module_function

    def text(value)
      value.to_s.unicode_normalize(:nfkc)
           .tr("\u00A0　", '  ')
           .gsub(/[[:space:]]+/, ' ')
           .strip
    end

    def title(value)
      text(value).downcase
    end

    def lecturer(value)
      text(value).downcase.gsub(/[[:space:]]+/, '')
    end

    def faculty(value)
      text(value).downcase
    end

    def lecture_key(title:, lecturer:, faculty:)
      Digest::SHA256.hexdigest([self.title(title), self.lecturer(lecturer), self.faculty(faculty)].join("\u001F"))
    end

    def checksum(value)
      Digest::SHA256.hexdigest(canonical(value))
    end

    def canonical(value)
      case value
      when Hash
        value.stringify_keys.sort.to_h.transform_values { |child| canonical(child) }.to_json
      when Array
        value.map { |child| canonical(child) }.to_json
      else
        value.to_s
      end
    end
  end
end
