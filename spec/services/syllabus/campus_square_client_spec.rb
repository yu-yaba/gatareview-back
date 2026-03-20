# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Syllabus::CampusSquareClient do
  describe '#normalize_body' do
    it 'converts an ASCII-8BIT response body into UTF-8 using the response charset' do
      client = described_class.new(base_url: 'https://example.com')
      raw_body = '<html><body>検索結果が最大表示件数（500）を超過しています。</body></html>'
                 .encode(Encoding::UTF_8)
                 .dup
                 .force_encoding(Encoding::ASCII_8BIT)
      response = instance_double(Net::HTTPOK, body: raw_body, type_params: { 'charset' => 'UTF-8' })

      normalized_body = client.send(:normalize_body, response)

      expect(normalized_body.encoding).to eq(Encoding::UTF_8)
      expect(normalized_body).to include('検索結果が最大表示件数（500）を超過しています。')
    end
  end
end
