# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::LecturesController, type: :request do
  describe 'GET /api/v1/lectures' do
    context '講義が存在する場合' do
      let!(:lecture) { FactoryBot.create(:lecture) }
      let!(:review) { FactoryBot.create(:review, lecture: lecture) }

      it '講義一覧を取得できること' do
        get '/api/v1/lectures'

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['lectures'].first['title']).to eq(lecture.title)
        expect(json['lectures'].first['lecturer']).to eq(lecture.lecturer)
        expect(json['lectures'].first['faculty']).to eq(lecture.faculty)
        expect(json['lectures'].first['avg_rating']).to be_present
        expect(json['lectures'].first['review_count']).to eq(1)
        expect(json['lectures'].first['offering']).to be_nil
        expect(json['pagination']).to be_present
      end
    end

    context '講義が存在しない場合' do
      it '空配列を返すこと' do
        get '/api/v1/lectures'

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['lectures']).to eq([])
        expect(json['pagination']).to include('current_page' => 1, 'total_count' => 0)
      end
    end

    context '開講情報で絞り込む場合' do
      let!(:matching_lecture) { FactoryBot.create(:lecture, title: '第3ターム月2講義') }
      let!(:matching_offering) do
        LectureOffering.create!(
          lecture: matching_lecture,
          year: 2026,
          registration_code: '261H2001',
          shozoku_code: '01',
          term_label: '第3ターム',
          term_code: 'C'
        )
      end
      let!(:matching_slot) { OfferingSlot.create!(lecture_offering: matching_offering, day: 1, period: 2) }
      let!(:different_slot_lecture) { FactoryBot.create(:lecture, title: '第3ターム火3講義') }
      let!(:different_slot_offering) do
        LectureOffering.create!(
          lecture: different_slot_lecture,
          year: 2026,
          registration_code: '261H2002',
          shozoku_code: '01',
          term_label: '第3ターム',
          term_code: 'C'
        )
      end
      let!(:different_slot) { OfferingSlot.create!(lecture_offering: different_slot_offering, day: 2, period: 3) }
      let!(:past_lecture) { FactoryBot.create(:lecture, title: '過年度第3ターム講義') }
      let!(:past_offering) do
        LectureOffering.create!(
          lecture: past_lecture,
          year: 2025,
          registration_code: '251H2001',
          shozoku_code: '01',
          term_label: '第3ターム',
          term_code: 'C'
        )
      end
      let!(:past_slot) { OfferingSlot.create!(lecture_offering: past_offering, day: 1, period: 2) }
      let!(:lecture_without_offering) { FactoryBot.create(:lecture, title: '開講情報なし講義') }

      it 'ターム・曜限をANDで絞り込み、最新年度を既定値にすること' do
        get '/api/v1/lectures', params: { term: 3, day: 1, period: 2 }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json.fetch('lectures').map { |lecture| lecture.fetch('id') }).to eq([matching_lecture.id])
        expect(json.dig('lectures', 0, 'offering')).to include(
          'year' => 2026,
          'term_label' => '第3ターム',
          'term_numbers' => [3],
          'slots' => [{ 'day' => 1, 'period' => 2 }],
          'syllabus_url' => 'https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/01/01_261H2001_ja_JP.html'
        )
        expect(json.fetch('lectures').map { |lecture| lecture.fetch('id') }).not_to include(lecture_without_offering.id)
      end

      it '指定年度を使って過年度の開講も検索できること' do
        get '/api/v1/lectures', params: { term: 3, day: 1, period: 2, offering_year: 2025 }

        expect(JSON.parse(response.body).fetch('lectures').map { |lecture| lecture.fetch('id') }).to eq([past_lecture.id])
      end

      it '絞り込みに一致した過年度の開講情報を返すこと' do
        multi_year_lecture = FactoryBot.create(:lecture, title: '複数年度開講講義')
        old_offering = LectureOffering.create!(
          lecture: multi_year_lecture,
          year: 2025,
          registration_code: '251H2010',
          shozoku_code: '01',
          term_label: '第3ターム',
          term_code: 'C'
        )
        OfferingSlot.create!(lecture_offering: old_offering, day: 1, period: 2)
        latest_offering = LectureOffering.create!(
          lecture: multi_year_lecture,
          year: 2026,
          registration_code: '261H2010',
          shozoku_code: '01',
          term_label: '第1ターム',
          term_code: 'A'
        )
        OfferingSlot.create!(lecture_offering: latest_offering, day: 2, period: 3)

        get '/api/v1/lectures', params: { term: 3, day: 1, period: 2, offering_year: 2025 }

        lecture_json = JSON.parse(response.body).fetch('lectures').find { |item| item.fetch('id') == multi_year_lecture.id }
        expect(lecture_json.fetch('offering')).to include(
          'id' => old_offering.id,
          'year' => 2025,
          'term_numbers' => [3],
          'slots' => [{ 'day' => 1, 'period' => 2 }]
        )
      end

      it '集中・その他はslotなしでもターム検索できること' do
        intensive_lecture = FactoryBot.create(:lecture, title: '集中講義')
        LectureOffering.create!(
          lecture: intensive_lecture,
          year: 2026,
          registration_code: '261H2003',
          shozoku_code: '01',
          term_label: '集中',
          term_code: '4'
        )

        get '/api/v1/lectures', params: { term: 'intensive' }

        expect(JSON.parse(response.body).fetch('lectures').map { |lecture| lecture.fetch('id') }).to include(intensive_lecture.id)
      end

      it 'missingの開講を通常検索から除外すること' do
        missing_lecture = FactoryBot.create(:lecture, title: '未掲載になった講義')
        missing_offering = LectureOffering.create!(
          lecture: missing_lecture,
          year: 2026,
          registration_code: '261H2999',
          shozoku_code: '01',
          term_code: 'C',
          source_status: 'missing'
        )
        OfferingSlot.create!(lecture_offering: missing_offering, day: 1, period: 2)

        get '/api/v1/lectures', params: { term: 3, day: 1, period: 2 }

        ids = JSON.parse(response.body).fetch('lectures').map { |lecture| lecture.fetch('id') }
        expect(ids).to include(matching_lecture.id)
        expect(ids).not_to include(missing_lecture.id)
      end

      it 'シラバス詳細の事実情報で絞り込めること' do
        LectureOfferingDetail.create!(lecture_offering: matching_offering, campus: '五十嵐', target_years: [2])

        get '/api/v1/lectures', params: { campus: '五十嵐', target_year: 2 }

        expect(JSON.parse(response.body).fetch('lectures').map { |lecture| lecture.fetch('id') }).to eq([matching_lecture.id])
      end
    end

    context 'レビュー年度・タームで絞り込む場合' do
      it '移行前後のカラムを同じ条件で検索できること' do
        legacy_lecture = FactoryBot.create(:lecture, title: '旧レビュー形式の講義')
        legacy_review = FactoryBot.create(:review, lecture: legacy_lecture, period_year: '2026', period_term: '1ターム')
        legacy_review.update_columns(academic_year: nil, term_code: nil)
        new_lecture = FactoryBot.create(:lecture, title: '新レビュー形式の講義')
        FactoryBot.create(:review, lecture: new_lecture, academic_year: 2026, term_code: 'A')

        get '/api/v1/lectures', params: { academic_year: 2026, review_term_code: 'A' }

        expect(JSON.parse(response.body).fetch('lectures').map { |lecture| lecture.fetch('id') })
          .to contain_exactly(legacy_lecture.id, new_lecture.id)
      end
    end
  end

  describe 'GET /api/v1/lectures/:id' do
    let!(:lecture) { FactoryBot.create(:lecture) }

    context '指定したIDの講義が存在する場合' do
      it '講義の詳細を取得できること' do
        get "/api/v1/lectures/#{lecture.id}"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['title']).to eq(lecture.title)
        expect(json['lecturer']).to eq(lecture.lecturer)
        expect(json['faculty']).to eq(lecture.faculty)
      end

      it '代表offeringを含めて返すこと' do
        offering = LectureOffering.create!(
          lecture: lecture,
          year: 2026,
          registration_code: '261H2001',
          shozoku_code: '01',
          term_label: '第1ターム',
          term_code: 'A'
        )
        OfferingSlot.create!(lecture_offering: offering, day: 1, period: 2)

        get "/api/v1/lectures/#{lecture.id}"

        expect(JSON.parse(response.body).fetch('offering')).to include(
          'year' => 2026,
          'term_label' => '第1ターム',
          'term_numbers' => [1],
          'slots' => [{ 'day' => 1, 'period' => 2 }]
        )
      end

      it 'offering_idで指定した過年度の開講情報を返すこと' do
        old_offering = LectureOffering.create!(
          lecture: lecture,
          year: 2025,
          registration_code: '251H2020',
          shozoku_code: '01',
          term_label: '第3ターム',
          term_code: 'C'
        )
        OfferingSlot.create!(lecture_offering: old_offering, day: 1, period: 2)
        LectureOffering.create!(
          lecture: lecture,
          year: 2026,
          registration_code: '261H2020',
          shozoku_code: '01',
          term_label: '第1ターム',
          term_code: 'A'
        )

        get "/api/v1/lectures/#{lecture.id}", params: { offering_id: old_offering.id }

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body).fetch('offering')).to include(
          'id' => old_offering.id,
          'year' => 2025,
          'term_numbers' => [3],
          'slots' => [{ 'day' => 1, 'period' => 2 }]
        )
      end

      it '別講義またはmissingのoffering_idを拒否すること' do
        other_lecture = FactoryBot.create(:lecture, title: '別の講義')
        other_offering = LectureOffering.create!(
          lecture: other_lecture,
          year: 2025,
          registration_code: '251H2021',
          shozoku_code: '01'
        )
        missing_offering = LectureOffering.create!(
          lecture: lecture,
          year: 2025,
          registration_code: '251H2022',
          shozoku_code: '01',
          source_status: 'missing'
        )

        get "/api/v1/lectures/#{lecture.id}", params: { offering_id: other_offering.id }
        expect(response).to have_http_status(:not_found)

        get "/api/v1/lectures/#{lecture.id}", params: { offering_id: missing_offering.id }
        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)).to include('error' => '指定された開講情報はこの講義に存在しません。')
      end

      it '空・非数値・非正数・範囲外・配列のoffering_idを拒否すること' do
        offering = LectureOffering.create!(
          lecture: lecture,
          year: 2026,
          registration_code: '261H2023',
          shozoku_code: '01'
        )
        invalid_values = ['', 'abc', '0', '-1', '9223372036854775808', [offering.id, offering.id]]

        invalid_values.each do |offering_id|
          get "/api/v1/lectures/#{lecture.id}", params: { offering_id: offering_id }

          expect(response).to have_http_status(:not_found), "offering_id=#{offering_id.inspect}"
          expect(JSON.parse(response.body)).to include('error' => '指定された開講情報はこの講義に存在しません。')
        end
      end
    end

    context '指定したIDの講義が存在しない場合' do
      it 'エラーを返すこと' do
        get '/api/v1/lectures/0'

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/lectures/no_reviews' do
    let!(:lectures_without_reviews) { FactoryBot.create_list(:lecture, 6) }
    let!(:reviewed_lecture) { FactoryBot.create(:lecture) }
    let!(:review) { FactoryBot.create(:review, lecture: reviewed_lecture) }

    it 'レビュー未投稿の講義のみを軽量ランダムで返すこと' do
      allow(SecureRandom).to receive(:random_number).with(3).and_return(1)

      get '/api/v1/lectures/no_reviews'

      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      lecture_ids = json.fetch('lectures').map { |lecture_json| lecture_json.fetch('id') }

      expect(lecture_ids).to eq(lectures_without_reviews.map(&:id)[1, 4])
      expect(lecture_ids).not_to include(reviewed_lecture.id)
    end
  end

  describe 'POST /api/v1/lectures' do
    let(:admin_user) { FactoryBot.create(:user, email: 'admin@example.com') }
    let(:valid_params) do
      {
        lecture: {
          title: '新しい講義',
          lecturer: '新しい講師',
          faculty: '新しい学部'
        }
      }
    end

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('ADMIN_EMAILS', '').and_return('admin@example.com')
      allow(ENV).to receive(:fetch).with('ADMIN_EMAIL', nil).and_return(nil)
      allow(AuthorizeApiRequest).to receive(:call).and_return({ result: admin_user })
    end

    context '有効なパラメータの場合' do
      it '講義を作成できること' do
        expect do
          post '/api/v1/lectures', params: valid_params
        end.to change(Lecture, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['title']).to eq('新しい講義')
        expect(json['lecturer']).to eq('新しい講師')
        expect(json['faculty']).to eq('新しい学部')
      end
    end

    context '無効なパラメータの場合' do
      it '講義を作成できないこと' do
        invalid_params = {
          lecture: {
            title: '',
            lecturer: '新しい講師',
            faculty: '新しい学部'
          }
        }

        expect do
          post '/api/v1/lectures', params: invalid_params
        end.not_to change(Lecture, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
