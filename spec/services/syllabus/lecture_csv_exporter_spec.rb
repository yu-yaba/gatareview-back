# frozen_string_literal: true

require 'rails_helper'
require 'csv'
require 'tmpdir'

RSpec.describe Syllabus::LectureCsvExporter do
  class FakeCampusSquareClient
    attr_reader :requests

    def initialize(search_pages: {}, paged_results: {})
      @search_pages = search_pages
      @paged_results = paged_results
      @requests = []
    end

    def search_results(year:, faculty_code:, term_code: nil, display_count: Syllabus::LectureCsvExporter::DISPLAY_COUNT)
      requests << [:search, year.to_s, faculty_code, term_code, display_count]
      @search_pages.fetch([year.to_s, faculty_code, term_code, display_count]) { no_results_html }
    end

    def fetch_results_page(flow_execution_key:, page_count:, display_count: Syllabus::LectureCsvExporter::DISPLAY_COUNT)
      requests << [:page, flow_execution_key, page_count, display_count]
      @paged_results.fetch([flow_execution_key, page_count, display_count])
    end

    private

    def no_results_html
      <<~HTML
        <html>
          <body>
            <span class="error">#{Syllabus::LectureCsvExporter::NO_RESULTS_MESSAGE}</span>
            <form name="KeywordForm">
              <input type="hidden" name="_flowExecutionKey" value="no-results-flow">
            </form>
          </body>
        </html>
      HTML
    end
  end

  def result_page_html(flow_key:, total_count:, rows:)
    rendered_rows = rows.each_with_index.map do |row, index|
      title, lecturer, semester_label, term_label, day_periods, registration_code = row
      semester_label ||= '第1学期'
      term_label ||= '第1ターム'
      day_periods ||= '他'
      registration_code ||= format('250A%04d', index + 1)
      <<~ROW
        <tr>
          <td>#{index + 1}</td>
          <td>#{semester_label}</td>
          <td>#{term_label}</td>
          <td>#{day_periods}</td>
          <td>#{registration_code}</td>
          <td>#{title}</td>
          <td>#{lecturer}</td>
          <td>参照</td>
        </tr>
      ROW
    end.join

    <<~HTML
      <html>
        <body>
          <table width="100%">
            <tbody>
              <tr>
                <td>1～#{rows.size}/#{total_count}件表示</td>
              </tr>
            </tbody>
          </table>
          <table class="normal">
            <thead>
              <tr>
                <th>No.</th>
                <th>学期</th>
                <th>開講</th>
                <th>曜日・時限</th>
                <th>開講番号</th>
                <th>科目名</th>
                <th>担当教員</th>
                <th>参照</th>
              </tr>
            </thead>
            <tbody>
              #{rendered_rows}
            </tbody>
          </table>
          <form name="KeywordForm">
            <input type="hidden" name="_flowExecutionKey" value="#{flow_key}">
          </form>
        </body>
      </html>
    HTML
  end

  def over_limit_html
    <<~HTML
      <html>
        <body>
          <span class="error">#{described_class::OVER_LIMIT_MESSAGE}</span>
          <form name="KeywordForm">
            <input type="hidden" name="_flowExecutionKey" value="over-limit-flow">
          </form>
        </body>
      </html>
    HTML
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @tmp_dir = Pathname(dir)
      example.run
    end
  end

  let(:timestamp) { Time.zone.local(2026, 1, 2, 3, 4, 5) }

  it 'exports a CSV file with pagination and normalized lecturer names' do
    client = FakeCampusSquareClient.new(
      search_pages: {
        ['2026', '01', nil, 200] => result_page_html(
          flow_key: 'humanities-flow',
          total_count: 3,
          rows: [
            ['Beta Course', "太田　凌嘉\n"],
            ['Alpha Course', '中本  真人']
          ]
        )
      },
      paged_results: {
        ['humanities-flow', 2, 200] => result_page_html(
          flow_key: 'humanities-flow',
          total_count: 3,
          rows: [['Gamma Course', '原　直史']]
        )
      }
    )

    result = described_class.new(
      year: 2026,
      output_dir: @tmp_dir,
      client: client,
      timestamp: timestamp,
      sleeper: ->(_) {}
    ).call

    expect(result.path.basename.to_s).to eq('lectureData_2026_20260102_030405.csv')
    expect(result.row_count).to eq(3)
    expect(result.faculty_counts['H:人文学部']).to eq(3)
    expect(CSV.read(result.path)).to eq(
      [
        ['Alpha Course', '中本 真人', 'H:人文学部', '2026', '250A0002', '01', '第1学期', '第1ターム', '他'],
        ['Beta Course', '太田 凌嘉', 'H:人文学部', '2026', '250A0001', '01', '第1学期', '第1ターム', '他'],
        ['Gamma Course', '原 直史', 'H:人文学部', '2026', '250A0001', '01', '第1学期', '第1ターム', '他']
      ]
    )
    expect(client.requests).to include([:page, 'humanities-flow', 2, 200])
  end

  it 'splits over-limit faculties by term codes' do
    client = FakeCampusSquareClient.new(
      search_pages: {
        ['2026', '03', nil, 200] => over_limit_html,
        ['2026', '03', '3', 200] => result_page_html(
          flow_key: 'education-term-3',
          total_count: 1,
          rows: [['教育学概論', '佐藤　花子']]
        ),
        ['2026', '03', '4', 200] => result_page_html(
          flow_key: 'education-term-4',
          total_count: 1,
          rows: [['教育実習', '山田 太郎']]
        )
      }
    )

    result = described_class.new(
      year: 2026,
      output_dir: @tmp_dir,
      client: client,
      timestamp: timestamp,
      sleeper: ->(_) {}
    ).call

    expect(result.faculty_counts['K:教育学部']).to eq(2)
    expect(CSV.read(result.path)).to include(
      ['教育学概論', '佐藤 花子', 'K:教育学部', '2026', '250A0001', '03', '第1学期', '第1ターム', '他'],
      ['教育実習', '山田 太郎', 'K:教育学部', '2026', '250A0001', '03', '第1学期', '第1ターム', '他']
    )
    expect(client.requests).to include([:search, '2026', '03', nil, 200])
    expect(client.requests).to include([:search, '2026', '03', '3', 200])
    expect(client.requests).to include([:search, '2026', '03', '4', 200])
  end

  it 'fails without leaving a final CSV when a split term still exceeds the limit' do
    client = FakeCampusSquareClient.new(
      search_pages: {
        ['2026', '03', nil, 200] => over_limit_html,
        ['2026', '03', '1', 200] => over_limit_html
      }
    )

    exporter = described_class.new(
      year: 2026,
      output_dir: @tmp_dir,
      client: client,
      timestamp: timestamp,
      sleeper: ->(_) {}
    )

    expect { exporter.call }.to raise_error(described_class::Error, /教育学部/)
    expect(Dir.glob(@tmp_dir.join('*.csv').to_s)).to be_empty
  end

  it 'exports all v2 fields and normalizes multiple day periods' do
    client = FakeCampusSquareClient.new(
      search_pages: {
        ['2026', '01', nil, 200] => result_page_html(
          flow_key: 'humanities-flow', total_count: 1,
          rows: [['心理学　概論Ａ', '新美　亮輔', '第1学期', '第1,2ターム', '月２, 木 2', '261H2001']]
        )
      }
    )

    result = described_class.new(year: 2026, output_dir: @tmp_dir, client: client, timestamp: timestamp, sleeper: ->(_) {}).call

    expect(CSV.read(result.path)).to include(
      ['心理学 概論Ａ', '新美 亮輔', 'H:人文学部', '2026', '261H2001', '01', '第1学期', '第1,2ターム', '月2|木2']
    )
  end
end
