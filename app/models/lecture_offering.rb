# frozen_string_literal: true

# シラバス上の「年度ごとの開講」。開講番号は年度ごとに変わるため lectures とは分離して持つ
class LectureOffering < ApplicationRecord
  SYLLABUS_BASE = 'https://syllabus.niigata-u.ac.jp/syllabusHtml'

  # CampusSquare の開講区分ラベル → 開講区分コード（検索フォームの kaikoKubunCode と同一体系）
  TERM_LABEL_TO_CODE = {
    '第1学期' => '1',
    '第2学期' => '2',
    '通年' => '3',
    '集中' => '4',
    '年度跨り' => '5',
    '時間外' => '9',
    '第1ターム' => 'A',
    '第2ターム' => 'B',
    '第3ターム' => 'C',
    '第4ターム' => 'D',
    '第1,2ターム' => 'E',
    '第3,4ターム' => 'F',
    '第2,3ターム' => 'G',
    '第1～3ターム' => 'H',
    '第2～4ターム' => 'I'
  }.freeze

  # 開講区分コード → 該当タームの集合。①の検索・④の時間割自動配置で共用する唯一の定義。
  # 空配列はターム制グリッド外（集中・時間外など）を表す
  TERM_EXPANSION = {
    'A' => [1], 'B' => [2], 'C' => [3], 'D' => [4],
    'E' => [1, 2], 'F' => [3, 4], 'G' => [2, 3], 'H' => [1, 2, 3], 'I' => [2, 3, 4],
    '1' => [1, 2],       # 第1学期（セメスター科目）
    '2' => [3, 4],       # 第2学期
    '3' => [1, 2, 3, 4], # 通年
    '4' => [],           # 集中
    '5' => [],           # 年度跨り
    '9' => []            # 時間外
  }.freeze

  belongs_to :lecture
  has_many :offering_slots, dependent: :destroy

  validates :year, :registration_code, :shozoku_code, presence: true
  validates :registration_code, uniqueness: { scope: :year }

  def self.term_code_for(label)
    normalized = label.to_s.gsub(/[[:space:]]/, '').tr('，、', ',,').tr('〜', '～')
    TERM_LABEL_TO_CODE[normalized]
  end

  def syllabus_url
    "#{SYLLABUS_BASE}/#{year}/#{shozoku_code}/#{shozoku_code}_#{registration_code}_ja_JP.html"
  end

  def term_numbers
    TERM_EXPANSION.fetch(term_code, [])
  end

  def intensive?
    term_numbers.empty?
  end
end
