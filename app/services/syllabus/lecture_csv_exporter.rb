# frozen_string_literal: true

require 'csv'
require 'fileutils'
require 'nokogiri'
require 'pathname'
require 'tempfile'

module Syllabus
  class LectureCsvExporter
    Error = Class.new(StandardError)

    DISPLAY_COUNT = 200
    OVER_LIMIT_MESSAGE = '検索結果が最大表示件数（500）を超過しています。検索条件を追加してください。'
    NO_RESULTS_MESSAGE = '入力された条件に該当する開講科目は存在しません。　検索条件を変更してください。'
    TERM_CODES = %w[1 2 3 4 5 9 A B C D E F G H I].freeze
    FACULTY_CONFIGS = [
      { code: '01', faculty: 'H:人文学部' },
      { code: '03', faculty: 'K:教育学部' },
      { code: '04', faculty: 'L:法学部' },
      { code: '0C', faculty: 'E:経済科学部' },
      { code: '06', faculty: 'S:理学部' },
      { code: '07', faculty: 'M:医学部' },
      { code: '08', faculty: 'D:歯学部' },
      { code: '09', faculty: 'T:工学部' },
      { code: '0A', faculty: 'A:農学部' },
      { code: '0B', faculty: 'X:創生学部' },
      { code: '84', faculty: 'G:教養科目' }
    ].freeze

    Result = Struct.new(:path, :row_count, :faculty_counts, keyword_init: true)
    ParsedSearchPage = Struct.new(:rows, :flow_execution_key, :total_count, :over_limit, :no_results, keyword_init: true)

    def initialize(year:, output_dir: Rails.root, client: CampusSquareClient.new, timestamp: Time.current)
      @year = year.to_s
      @output_dir = Pathname.new(output_dir.to_s)
      @client = client
      @timestamp = timestamp
    end

    def call
      validate_year!
      FileUtils.mkdir_p(output_dir)

      rows = FACULTY_CONFIGS.flat_map do |faculty_config|
        fetch_faculty_rows(faculty_config)
      end

      normalized_rows = rows
                        .map { |row| normalize_row(row) }
                        .uniq
                        .sort_by { |title, lecturer, faculty| [faculty_order.fetch(faculty), title, lecturer, faculty] }
      faculty_counts = build_faculty_counts(normalized_rows)

      path = write_csv(normalized_rows)
      Result.new(path: path, row_count: normalized_rows.size, faculty_counts: faculty_counts)
    end

    private

    attr_reader :year, :output_dir, :client, :timestamp

    def validate_year!
      raise ArgumentError, 'YEAR is required. Example: YEAR=2026' if year.blank?
      raise ArgumentError, "YEAR must be a 4-digit year: #{year}" unless year.match?(/\A\d{4}\z/)
    end

    def fetch_faculty_rows(faculty_config)
      page = search(faculty_config[:code])
      if page.over_limit
        TERM_CODES.flat_map do |term_code|
          split_page = search(faculty_config[:code], term_code: term_code)
          if split_page.over_limit
            raise Error, "#{faculty_config[:faculty]} は開講=#{term_code} でも 500 件を超過しました。追加の分割条件が必要です。"
          end

          rows_for_page(split_page, faculty_config[:faculty])
        end
      else
        rows_for_page(page, faculty_config[:faculty])
      end
    end

    def search(faculty_code, term_code: nil)
      html = client.search_results(
        year: year,
        faculty_code: faculty_code,
        term_code: term_code,
        display_count: DISPLAY_COUNT
      )
      parse_search_page(html)
    end

    def rows_for_page(page, faculty)
      return [] if page.no_results

      rows = page.rows.map { |row| [row[0], row[1], faculty] }
      return rows if page.total_count <= DISPLAY_COUNT

      total_pages = (page.total_count.to_f / DISPLAY_COUNT).ceil
      (2..total_pages).each do |page_count|
        html = client.fetch_results_page(
          flow_execution_key: page.flow_execution_key,
          page_count: page_count,
          display_count: DISPLAY_COUNT
        )
        parsed_page = parse_search_page(html)
        if parsed_page.over_limit
          raise Error, "#{faculty} のページング取得中に 500 件超過レスポンスが返されました。"
        end
        if parsed_page.no_results
          raise Error, "#{faculty} のページ #{page_count} が空でした。ページング取得に失敗した可能性があります。"
        end

        rows.concat(parsed_page.rows.map { |row| [row[0], row[1], faculty] })
      end

      rows
    end

    def parse_search_page(html)
      return ParsedSearchPage.new(over_limit: true, no_results: false, rows: [], total_count: nil, flow_execution_key: nil) if html.include?(OVER_LIMIT_MESSAGE)
      return ParsedSearchPage.new(over_limit: false, no_results: true, rows: [], total_count: 0, flow_execution_key: parse_flow_execution_key(html)) if html.include?(NO_RESULTS_MESSAGE)

      doc = Nokogiri::HTML(html)
      rows = parse_rows(doc)
      total_count = parse_total_count(doc)
      flow_execution_key = parse_flow_execution_key(doc)

      if rows.empty? || total_count.nil? || flow_execution_key.blank?
        raise Error, 'シラバス検索結果の解析に失敗しました。HTML 構造が変わった可能性があります。'
      end

      ParsedSearchPage.new(
        rows: rows,
        flow_execution_key: flow_execution_key,
        total_count: total_count,
        over_limit: false,
        no_results: false
      )
    end

    def parse_rows(doc)
      result_table = doc.css('table.normal').find do |table|
        headers = table.css('th').map { |header| compact_text(header.text) }
        headers.include?('科目名') && headers.include?('担当教員')
      end
      return [] unless result_table

      result_table.css('tbody > tr').each_with_object([]) do |row, parsed_rows|
        cells = row.css('td')
        next if cells.size < 7

        title = compact_text(cells[5].text)
        lecturer = normalize_lecturer(cells[6].text)
        next if title.blank? || lecturer.blank?

        parsed_rows << [title, lecturer]
      end
    end

    def parse_total_count(doc)
      match = doc.text.match(/(\d+)～(\d+)\/(\d+)件表示/)
      match && match[3].to_i
    end

    def parse_flow_execution_key(source)
      doc = source.is_a?(Nokogiri::XML::Node) ? source : Nokogiri::HTML(source)
      doc.css('input[name="_flowExecutionKey"]').last&.[]('value')
    end

    def normalize_row(row)
      [
        compact_text(row[0]),
        normalize_lecturer(row[1]),
        compact_text(row[2])
      ]
    end

    def compact_text(text)
      text.to_s.tr("\u00A0", ' ').gsub(/[[:space:]]+/, ' ').strip
    end

    def normalize_lecturer(text)
      text.to_s.tr("\u00A0", ' ').tr('　', ' ').gsub(/[[:space:]]+/, ' ').strip
    end

    def write_csv(rows)
      temp_file = Tempfile.new(["lectureData_#{year}_", '.csv'], output_dir.to_s)
      CSV.open(temp_file.path, 'w', write_headers: false) do |csv|
        rows.each { |row| csv << row }
      end

      final_path = next_available_path
      FileUtils.mv(temp_file.path, final_path)
      final_path
    ensure
      temp_file&.close!
    end

    def next_available_path
      base_name = "lectureData_#{year}_#{timestamp.strftime('%Y%m%d_%H%M%S')}"
      candidate = output_dir.join("#{base_name}.csv")
      return candidate unless candidate.exist?

      suffix = 2
      loop do
        candidate = output_dir.join("#{base_name}_#{suffix}.csv")
        return candidate unless candidate.exist?

        suffix += 1
      end
    end

    def faculty_order
      @faculty_order ||= FACULTY_CONFIGS.each_with_index.to_h { |config, index| [config[:faculty], index] }
    end

    def build_faculty_counts(rows)
      counts = FACULTY_CONFIGS.to_h { |config| [config[:faculty], 0] }
      rows.each do |(_, _, faculty)|
        counts[faculty] += 1 if counts.key?(faculty)
      end
      counts
    end
  end
end
