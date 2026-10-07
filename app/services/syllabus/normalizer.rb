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

    # 既存のsource_checksumはscalarを文字列化する旧形式を維持する。
    # import manifestだけは型も完全性の一部として扱い、nil/空文字や数値/文字列を区別する。
    def typed_checksum(value)
      Digest::SHA256.hexdigest(typed_canonical(value))
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

    def typed_canonical(value)
      JSON.generate(typed_value(value))
    end

    def typed_value(value)
      case value
      when Hash
        value.stringify_keys.sort.to_h.transform_values { |child| typed_value(child) }
      when Array
        value.map { |child| typed_value(child) }
      else
        value
      end
    end

    private_class_method :typed_value
  end
end
