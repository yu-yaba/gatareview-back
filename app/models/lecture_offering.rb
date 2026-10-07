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
  belongs_to :syllabus_organization, optional: true
  belongs_to :first_seen_import_run, class_name: 'SyllabusImportRun', optional: true, inverse_of: :first_seen_offerings
  belongs_to :last_seen_import_run, class_name: 'SyllabusImportRun', optional: true, inverse_of: :last_seen_offerings
  belongs_to :missing_since_import_run, class_name: 'SyllabusImportRun', optional: true, inverse_of: :missing_since_offerings
  has_one :lecture_offering_detail, dependent: :destroy
  has_many :reviews, dependent: :nullify
  has_many :timetable_entries, dependent: :nullify

  validates :year, :registration_code, :shozoku_code, presence: true
  validates :registration_code, uniqueness: { scope: :year }
  validates :term_code, inclusion: { in: TERM_EXPANSION.keys }, allow_nil: true
  validates :schedule_kind, inclusion: { in: %w[regular intensive other unknown] }
  validates :source_status, inclusion: { in: %w[active missing] }

  scope :active, -> { where(source_status: 'active') }
  scope :missing, -> { where(source_status: 'missing') }

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
    schedule_kind == 'intensive' || term_code == '4'
  end

  def active?
    source_status == 'active'
  end

  def other_schedule?
    schedule_kind == 'other' || %w[5 9].include?(term_code)
  end
end
