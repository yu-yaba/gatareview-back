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
        expect(json['lectures'].first).not_to have_key('offering')
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

    context '従来のレビュー年度・タームで絞り込む場合' do
      %w[newest highestRating mostReviewed].each do |sort|
        it "文字列の条件と#{sort}を併用して重複なく正しい件数を返すこと" do
          matching_lectures = FactoryBot.create_list(:lecture, 2)
          matching_lectures.each do |matching_lecture|
            FactoryBot.create_list(:review, 2, lecture: matching_lecture, period_year: '2026', period_term: '1ターム')
          end
          FactoryBot.create(:review, period_year: '2025', period_term: '1ターム')
          FactoryBot.create(:review, period_year: '2026', period_term: '2ターム')

          get '/api/v1/lectures', params: { period_year: '2026', period_term: '1ターム', sort: sort }

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body.fetch('lectures').pluck('id')).to contain_exactly(*matching_lectures.map(&:id))
          expect(response.parsed_body.dig('pagination', 'total_count')).to eq(2)
          expect(response.parsed_body.dig('pagination', 'total_pages')).to eq(1)
        end
      end
    end

    context '複数レビューがある授業をページ分割する場合' do
      let!(:reviewed_lectures) { FactoryBot.create_list(:lecture, 21) }
      let!(:unreviewed_lectures) { FactoryBot.create_list(:lecture, 4) }

      before do
        reviewed_lectures.each do |lecture|
          FactoryBot.create_list(:review, 2, lecture: lecture)
        end
      end

      {
        'newest' => 25,
        'highestRating' => 21,
        'mostReviewed' => 21,
        'unknown' => 25
      }.each do |sort, expected_count|
        it "#{sort}で授業数を数え、2ページ目にも正しい件数と統計を返すこと" do
          get '/api/v1/lectures', params: { sort: sort, page: 2 }

          expect(response).to have_http_status(:ok)
          json = response.parsed_body
          expect(json.fetch('pagination')).to include(
            'current_page' => 2, 'total_pages' => 2, 'total_count' => expected_count, 'per_page' => 20
          )
          expect(json.fetch('lectures').size).to eq(expected_count - 20)
          json.fetch('lectures').each do |lecture|
            reviewed = reviewed_lectures.any? { |record| record.id == lecture.fetch('id') }
            expect(lecture.fetch('review_count')).to eq(reviewed ? 2 : 0)
            expect(lecture.fetch('avg_rating')).to eq(reviewed ? 5 : 0)
          end
        end
      end

      it '最終ページの先でも総件数を維持して空配列を返すこと' do
        get '/api/v1/lectures', params: { page: 3 }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.fetch('lectures')).to eq([])
        expect(response.parsed_body.fetch('pagination')).to include(
          'current_page' => 3, 'total_pages' => 2, 'total_count' => 25
        )
      end
    end

    context '並び順の値が同じ授業が大量にある状態で全ページを辿る場合' do
      # CSV一括取り込みでは授業・レビューの作成日時が同じ値になるため、
      # 並び順の値が同じ授業が大量に並ぶ。その状態を再現する。
      let(:imported_at) { Time.zone.parse('2026-04-01 09:00:00') }
      let!(:lectures) { FactoryBot.create_list(:lecture, 70) }

      before do
        lectures.first(55).each_with_index do |lecture, index|
          FactoryBot.create_list(:review, (index % 3).zero? ? 2 : 1, lecture: lecture, rating: index.even? ? 4 : 3)
        end
        Lecture.update_all(created_at: imported_at, updated_at: imported_at)
        Review.update_all(created_at: imported_at, updated_at: imported_at)
      end

      def statistics_for(lecture)
        ratings = Review.where(lecture_id: lecture.id).pluck(:rating)
        { average: ratings.empty? ? nil : ratings.sum / ratings.size, count: ratings.size }
      end

      def expected_ids(sort)
        rows = lectures.map { |lecture| [lecture, statistics_for(lecture)] }
        reviewed = rows.select { |_lecture, stats| stats[:count].positive? }.map(&:first)
        case sort
        when 'newest'
          # 作成日時がすべて同じなので「レビューあり→なし」の順で、それぞれ新しいID順
          reviewed.map(&:id).sort.reverse + (lectures - reviewed).map(&:id).sort.reverse
        when 'highestRating'
          rows.select { |lecture, _| reviewed.include?(lecture) }
              .sort_by { |lecture, stats| [-stats[:average], -stats[:count], -lecture.id] }.map { |lecture, _| lecture.id }
        when 'mostReviewed'
          rows.select { |lecture, _| reviewed.include?(lecture) }
              .sort_by { |lecture, stats| [-stats[:count], -lecture.id] }.map { |lecture, _| lecture.id }
        else
          lectures.map(&:id).sort
        end
      end

      def walk_all_pages(sort)
        pagination = nil
        ids = []
        page = 1
        loop do
          get '/api/v1/lectures', params: { sort: sort, page: page }
          expect(response).to have_http_status(:ok)
          pagination ||= response.parsed_body.fetch('pagination')
          ids.concat(response.parsed_body.fetch('lectures').pluck('id'))
          break if page >= pagination.fetch('total_pages')

          page += 1
        end
        [ids, pagination]
      end

      %w[newest highestRating mostReviewed unknown].each do |sort|
        it "#{sort}で全ページを辿ると重複も欠けもなく、毎回同じ順序になること" do
          ids, pagination = walk_all_pages(sort)
          expected = expected_ids(sort)

          expect(pagination.fetch('total_count')).to eq(expected.size)
          expect(ids.tally.select { |_id, count| count > 1 }.keys).to eq([]), '複数ページに重複して表示される授業がある'
          expect(expected - ids).to eq([]), 'どのページにも表示されない授業がある'
          expect(ids).to eq(expected)
          expect(walk_all_pages(sort).first).to eq(ids)
        end
      end
    end

    context 'レビュー詳細で絞り込んで並び替える場合' do
      # 一致するレビューの評価は高いが、全レビューでは評価が低く、件数が多く、最新レビューも新しい授業
      let!(:mostly_low) { FactoryBot.create(:lecture) }
      # 一致するレビューだけを持つ授業
      let!(:steady) { FactoryBot.create(:lecture) }
      let!(:unmatched) { FactoryBot.create(:lecture) }

      before do
        [
          [mostly_low, 5, '不要', '2026-01-01 10:00'],
          [mostly_low, 1, '必要', '2026-03-01 10:00'],
          [mostly_low, 1, '必要', '2026-03-02 10:00'],
          [steady, 4, '不要', '2026-02-01 10:00'],
          [steady, 4, '不要', '2026-02-02 10:00'],
          [unmatched, 5, '必要', '2026-04-01 10:00']
        ].each do |lecture, rating, textbook, created_at|
          FactoryBot.create(:review, lecture: lecture, rating: rating, textbook: textbook,
                                     created_at: Time.zone.parse(created_at))
        end
      end

      {
        'highestRating' => %i[steady mostly_low],
        'mostReviewed' => %i[mostly_low steady],
        'newest' => %i[mostly_low steady]
      }.each do |sort, expected_order|
        it "#{sort}は表示中の平均評価・件数（全レビュー）の順に並び、絞り込みは表示対象だけを決めること" do
          get '/api/v1/lectures', params: { textbook: '不要', sort: sort }

          expect(response).to have_http_status(:ok)
          filtered = response.parsed_body.fetch('lectures')
          expect(filtered.pluck('id')).to eq(expected_order.map { |name| public_send(name).id })
          expect(filtered.to_h { |lecture| [lecture.fetch('id'), lecture.values_at('avg_rating', 'review_count')] })
            .to eq(mostly_low.id => [2.3, 3], steady.id => [4.0, 2])
          expect(response.parsed_body.dig('pagination', 'total_count')).to eq(2)

          get '/api/v1/lectures', params: { sort: sort }
          unfiltered_ids = response.parsed_body.fetch('lectures').pluck('id')
          expect(filtered.pluck('id')).to eq(unfiltered_ids & [mostly_low.id, steady.id])
        end
      end
    end

    context '検索語の前後や途中に空白がある場合' do
      let!(:exercise) { FactoryBot.create(:lecture, title: '数学演習') }
      let!(:linear_algebra) { FactoryBot.create(:lecture, title: '線形 代数') }
      # 既存データには空白が2つ続く担当教員名がある
      let!(:double_spaced) { FactoryBot.create(:lecture, title: '国語科教育法', lecturer: '伊藤  守') }
      let!(:english) { FactoryBot.create(:lecture, title: '英語') }

      def searched_ids(search)
        get '/api/v1/lectures', params: { search: search, sort: 'unknown' }
        expect(response).to have_http_status(:ok)
        response.parsed_body.fetch('lectures').pluck('id')
      end

      ['演習', ' 演習', '演習 ', "演習\u3000", "\u3000演習\u3000", "\t演習\n", "\uFEFF演習\u200B"].each do |search|
        it "#{search.inspect}でも空白なしと同じ結果になること" do
          expect(searched_ids(search)).to eq([exercise.id])
        end
      end

      ['線形 代数', "線形\u3000代数", " 線形 代数\u3000", "\u3000線形\u3000代数 "].each do |search|
        it "途中の空白が全角でも、前後に空白があっても#{search.inspect}で同じ結果になること" do
          expect(searched_ids(search)).to eq([linear_algebra.id])
        end
      end

      ['伊藤  守', " 伊藤  守\u3000", "伊藤\u3000\u3000守"].each do |search|
        it "途中の連続した空白は残し、#{search.inspect}で空白が2つ続く担当教員名を見つけること" do
          expect(searched_ids(search)).to eq([double_spaced.id])
        end
      end

      it '空白だけの検索語は検索条件なしと同じ結果になること' do
        expect(searched_ids(" \u3000\t")).to eq([exercise, linear_algebra, double_spaced, english].map(&:id))
      end
    end

    context '読み取りクエリの回数' do
      def count_selects
        statements = []
        subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
          next if payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name])

          statements << payload.fetch(:sql) if payload.fetch(:sql).match?(/\ASELECT/i)
        end
        yield
        statements.size
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      before do
        25.times do |index|
          lecture = FactoryBot.create(:lecture, title: "演習#{index}")
          FactoryBot.create_list(:review, 2, lecture: lecture, textbook: index.even? ? '不要' : '必要')
        end
      end

      %w[newest highestRating mostReviewed unknown].each do |sort|
        it "#{sort}で検索・学部・詳細条件を併用しても3回以内であること" do
          queries = count_selects do
            get '/api/v1/lectures', params: { sort: sort, search: '演習', faculty: '理学部', textbook: '不要', page: 1 }
          end

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body.fetch('lectures').size).to eq(13)
          expect(queries).to be <= 3
        end
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
        expect(json).not_to have_key('offering')
      end
    end

    context '指定したIDの講義が存在しない場合' do
      it 'エラーを返すこと' do
        get '/api/v1/lectures/0'

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/lectures/popular' do
    it 'レビュー数が同じ授業は新しいID順で、毎回同じ4件を返すこと' do
      most_reviewed = FactoryBot.create(:lecture)
      FactoryBot.create_list(:review, 2, lecture: most_reviewed)
      tied = FactoryBot.create_list(:lecture, 30).each { |lecture| FactoryBot.create(:review, lecture: lecture) }
      imported_at = Time.zone.parse('2026-04-01 09:00:00')
      Review.update_all(created_at: imported_at, updated_at: imported_at)

      responses = Array.new(3) do
        get '/api/v1/lectures/popular'
        expect(response).to have_http_status(:ok)
        response.parsed_body.fetch('lectures').pluck('id')
      end

      expect(responses.uniq).to eq([[most_reviewed.id, *tied.map(&:id).last(3).reverse]])
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

  describe 'GET /api/v1/lectures/sitemap' do
    it 'レビューがある授業だけを、ID順に最新レビューの投稿日（日本時間）つきで返すこと' do
      unreviewed = FactoryBot.create(:lecture)
      second = FactoryBot.create(:lecture)
      first = FactoryBot.create(:lecture)
      FactoryBot.create(:review, lecture: first, created_at: Time.utc(2026, 4, 1, 3, 0))
      # 日本時間では翌日（2026-05-02 00:30 JST）になる時刻
      FactoryBot.create(:review, lecture: first, created_at: Time.utc(2026, 5, 1, 15, 30))
      FactoryBot.create(:review, lecture: second, created_at: Time.utc(2025, 12, 31, 14, 59))

      get '/api/v1/lectures/sitemap'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'lectures' => [
          { 'id' => second.id, 'lastmod' => '2025-12-31' },
          { 'id' => first.id, 'lastmod' => '2026-05-02' }
        ]
      )
      expect(response.parsed_body.fetch('lectures').pluck('id')).not_to include(unreviewed.id)
    end

    it 'レビューの編集時刻（updated_at）では lastmod が変わらないこと' do
      lecture = FactoryBot.create(:lecture)
      review = FactoryBot.create(:review, lecture: lecture, created_at: Time.utc(2026, 4, 1, 3, 0))
      review.update_columns(updated_at: Time.utc(2026, 10, 1, 3, 0))

      get '/api/v1/lectures/sitemap'

      expect(response.parsed_body.fetch('lectures')).to eq([{ 'id' => lecture.id, 'lastmod' => '2026-04-01' }])
    end

    it '投稿日時の時刻・授業名・件数などの他の値を返さないこと' do
      FactoryBot.create(:review)

      get '/api/v1/lectures/sitemap'

      expect(response.parsed_body.keys).to eq(['lectures'])
      expect(response.parsed_body.fetch('lectures').first.keys).to eq(%w[id lastmod])
      expect(response.parsed_body.fetch('lectures').first.fetch('lastmod')).to match(/\A\d{4}-\d{2}-\d{2}\z/)
    end

    it '未ログインで取得でき、公開キャッシュ可能なCache-Controlを返すこと' do
      FactoryBot.create(:review)

      get '/api/v1/lectures/sitemap'

      expect(response).to have_http_status(:ok)
      cache_control = response.headers['Cache-Control'].split(/,\s*/)
      expect(cache_control).to include('public', 'max-age=3600')
      expect(cache_control).not_to include('private', 'no-store')
    end

    it 'レビューがなければ空配列を返すこと' do
      FactoryBot.create(:lecture)

      get '/api/v1/lectures/sitemap'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('lectures' => [])
    end

    it '授業数によらず1回のSELECTで返すこと' do
      FactoryBot.create_list(:lecture, 5).each { |lecture| FactoryBot.create_list(:review, 2, lecture: lecture) }
      statements = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        next if payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name])

        statements << payload.fetch(:sql) if payload.fetch(:sql).match?(/\ASELECT/i)
      end
      begin
        get '/api/v1/lectures/sitemap'
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(response.parsed_body.fetch('lectures').size).to eq(5)
      expect(statements.size).to eq(1)
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

    ['invalid lecture shape', [{ title: '不正な配列', lecturer: '講師', faculty: '学部' }]].each do |invalid_lecture|
      it 'オブジェクト以外の講義入力を400で拒否すること' do
        expect do
          post '/api/v1/lectures', params: { lecture: invalid_lecture }, as: :json
        end.not_to change(Lecture, :count)

        expect(response).to have_http_status(:bad_request)
      end

      it '不正な入力でも未認証なら先に401で拒否すること' do
        allow(AuthorizeApiRequest).to receive(:call).and_return({ result: nil })
        post '/api/v1/lectures', params: { lecture: invalid_lecture }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it '不正な入力でも非管理者なら先に403で拒否すること' do
        allow(AuthorizeApiRequest).to receive(:call).and_return({ result: FactoryBot.create(:user) })
        post '/api/v1/lectures', params: { lecture: invalid_lecture }, as: :json

        expect(response).to have_http_status(:forbidden)
      end
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
        expect(response.parsed_body).to eq('errors' => ['授業名を入力してください'])
      end

      it '登録済みの授業と同じなら、項目名つきの日本語の文言で422にすること' do
        existing = FactoryBot.create(:lecture)
        post '/api/v1/lectures', params: { lecture: existing.slice(:title, :lecturer, :faculty) }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('errors' => ['授業名・教授/講師名・学部が同じ授業はすでに登録されています'])
      end

      it '列の長さを超える入力は、500ではなく日本語の文言で422にすること' do
        post '/api/v1/lectures', params: { lecture: { title: 'あ' * 256, lecturer: '講師', faculty: '学部' } },
                                 as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('errors' => ['授業名は255文字以内で入力してください'])
      end
    end
  end
end
