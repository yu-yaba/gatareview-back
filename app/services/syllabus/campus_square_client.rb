# frozen_string_literal: true

require 'net/http'
require 'nokogiri'
require 'uri'

module Syllabus
  class CampusSquareClient
    BASE_URL = 'https://syllabus.niigata-u.ac.jp'
    ENTRY_PATH = '/campus-sy/'
    SEARCH_PATH = '/campus-sy/campussquare.do'
    USER_AGENT = 'GatareviewLectureExporter/1.0'

    def initialize(base_url: BASE_URL)
      @base_uri = URI(base_url)
      unless @base_uri.scheme == 'https' && @base_uri.host.present? && @base_uri.userinfo.nil?
        raise LectureCsvExporter::Error, 'シラバス接続先には認証情報を含まないHTTPS URLが必要です。'
      end

      @cookies = {}
    rescue URI::InvalidURIError
      raise LectureCsvExporter::Error, 'シラバス接続先URLが不正です。'
    end

    def search_results(year:, faculty_code:, term_code: nil, display_count: LectureCsvExporter::DISPLAY_COUNT)
      flow_execution_key = fetch_flow_execution_key
      form_data = {
        '_flowExecutionKey' => flow_execution_key,
        '_eventId' => 'search',
        'nendo' => year.to_s,
        'jikanwariShozokuCode' => faculty_code.to_s,
        '_displayCount' => display_count.to_s
      }
      form_data['kaikoKubunCode'] = term_code.to_s if term_code.present?

      post_html(SEARCH_PATH, form_data)
    end

    def fetch_results_page(flow_execution_key:, page_count:, display_count: LectureCsvExporter::DISPLAY_COUNT)
      query = URI.encode_www_form(
        '_flowExecutionKey' => flow_execution_key,
        '_eventId_paging' => '_eventId_paging',
        '_displayCount' => display_count.to_s,
        '_pageCount' => page_count.to_s
      )

      get_html("#{SEARCH_PATH}?#{query}")
    end

    private

    attr_reader :base_uri, :cookies

    def fetch_flow_execution_key
      html = get_html(ENTRY_PATH)
      doc = Nokogiri::HTML(html)
      flow_execution_key = doc.at_css('input[name="_flowExecutionKey"]')&.[]('value')
      raise LectureCsvExporter::Error, 'シラバス検索画面の flowExecutionKey を取得できませんでした。' if flow_execution_key.blank?

      flow_execution_key
    end

    def get_html(path_or_url, redirects_left: 5)
      request_with_redirects(Net::HTTP::Get, path_or_url, redirects_left: redirects_left)
    end

    def post_html(path_or_url, form_data, redirects_left: 5)
      request_with_redirects(Net::HTTP::Post, path_or_url, form_data: form_data, redirects_left: redirects_left)
    end

    def request_with_redirects(request_class, path_or_url, form_data: nil, redirects_left: 5)
      raise LectureCsvExporter::Error, 'シラバス検索へのリダイレクト回数が上限を超えました。' if redirects_left.negative?

      uri = resolve_uri(path_or_url)
      response = perform_request(request_class, uri, form_data: form_data)

      case response
      when Net::HTTPRedirection
        location = response['location']
        raise LectureCsvExporter::Error, 'シラバス検索から不正なリダイレクトが返されました。' if location.blank?

        next_uri = resolve_uri(location, relative_to: uri)
        get_html(next_uri.to_s, redirects_left: redirects_left - 1)
      else
        body = normalize_body(response)
        raise LectureCsvExporter::Error, 'シラバス検索から空のレスポンスが返されました。' if body.blank?

        body
      end
    end

    def perform_request(request_class, uri, form_data: nil)
      request = request_class.new(uri)
      request['User-Agent'] = USER_AGENT
      request['Accept-Language'] = 'ja-JP,ja;q=0.9'
      request['Cookie'] = cookie_header if cookie_header.present?
      request.set_form_data(form_data) if form_data

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 30) do |http|
        response = http.request(request)
        store_cookies(response)
        response
      end
    rescue StandardError => e
      raise LectureCsvExporter::Error, "シラバス検索への接続に失敗しました: #{e.message}"
    end

    def store_cookies(response)
      Array(response.get_fields('Set-Cookie')).each do |cookie|
        name_value = cookie.split(';').first
        next if name_value.blank?

        name, value = name_value.split('=', 2)
        next if name.blank? || value.blank?

        cookies[name] = value
      end
    end

    def cookie_header
      cookies.map { |name, value| "#{name}=#{value}" }.join('; ')
    end

    def resolve_uri(path_or_url, relative_to: base_uri)
      uri = URI.join(relative_to.to_s, path_or_url.to_s)
      unless uri.scheme == 'https' && uri.host == base_uri.host && uri.port == base_uri.port && uri.userinfo.nil?
        raise LectureCsvExporter::Error, 'シラバス検索の接続先が許可されたHTTPS配信元と一致しません。'
      end

      uri
    rescue URI::InvalidURIError
      raise LectureCsvExporter::Error, 'シラバス検索の接続先URLが不正です。'
    end

    def normalize_body(response)
      raw_body = response.body.to_s
      return raw_body if raw_body.blank?

      encoding = resolve_response_encoding(response)
      raw_body.dup.force_encoding(encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    rescue StandardError => e
      raise LectureCsvExporter::Error, "シラバス検索レスポンスの文字コード変換に失敗しました: #{e.message}"
    end

    def resolve_response_encoding(response)
      charset = response.type_params&.[]('charset')
      return Encoding::UTF_8 if charset.blank?

      Encoding.find(charset)
    rescue ArgumentError
      Encoding::UTF_8
    end
  end
end
