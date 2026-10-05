# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Syllabus::CampusSquareClient do
  describe 'redirect safety' do
    let(:client) { described_class.new }
    let(:http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:start).and_yield(http)
    end

    def redirect_response(location)
      response = Net::HTTPFound.new('1.1', '302', 'Found')
      response['Location'] = location
      response
    end

    def success_response
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('<html>syllabus results</html>')
      response
    end

    it 'follows same-origin HTTPS redirects and retains the syllabus session cookie' do
      initial_response = redirect_response('/campus-sy/next')
      initial_response['Set-Cookie'] = 'syllabus_session=dummy-session; Path=/campus-sy; Secure'
      requests = []
      responses = [initial_response, success_response]
      allow(http).to receive(:request) do |request|
        requests << request
        responses.shift
      end

      expect(client.send(:get_html, '/campus-sy/')).to include('syllabus results')
      expect(requests.map(&:path)).to eq(['/campus-sy/', '/campus-sy/next'])
      expect(requests.last['Cookie']).to eq('syllabus_session=dummy-session')
      expect(Net::HTTP).to have_received(:start)
        .with('syllabus.niigata-u.ac.jp', 443, use_ssl: true, open_timeout: 10, read_timeout: 30).twice
    end

    it 'resolves relative redirect locations against the current request path' do
      requests = []
      responses = [redirect_response('next'), success_response]
      allow(http).to receive(:request) do |request|
        requests << request
        responses.shift
      end

      client.send(:get_html, '/campus-sy/current')

      expect(requests.last.path).to eq('/campus-sy/next')
    end

    [
      'https://outside.example/private',
      '//outside.example/private',
      'http://syllabus.niigata-u.ac.jp/private',
      'http://127.0.0.1:9999/private',
      'https://syllabus.niigata-u.ac.jp:444/private',
      'https://user:password@syllabus.niigata-u.ac.jp/private',
      "\u0000invalid-url"
    ].each do |location|
      it "rejects an untrusted redirect before any request to #{location.inspect}" do
        allow(http).to receive(:request).and_return(redirect_response(location))

        expect { client.send(:get_html, '/campus-sy/') }
          .to raise_error(Syllabus::LectureCsvExporter::Error, /HTTPS|URLが不正/)
        expect(http).to have_received(:request).once
        expect(Net::HTTP).to have_received(:start).once
      end
    end

    it 'stops a same-origin redirect loop at the existing redirect limit' do
      allow(http).to receive(:request).and_return(redirect_response('/campus-sy/'))

      expect { client.send(:get_html, '/campus-sy/') }
        .to raise_error(Syllabus::LectureCsvExporter::Error, /上限/)
      expect(http).to have_received(:request).exactly(6).times
    end

    it 'rejects a non-HTTPS base URL' do
      expect { described_class.new(base_url: 'http://syllabus.niigata-u.ac.jp') }
        .to raise_error(Syllabus::LectureCsvExporter::Error, /HTTPS/)
    end
  end

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
