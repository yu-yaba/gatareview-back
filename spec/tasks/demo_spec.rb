# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'demo:review_access_seed', type: :task do
  let(:task) { Rake.application['demo:review_access_seed'] }

  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/demo.rake').to_s
    example.run
  ensure
    Rake.application = original_application
  end

  it 'aborts in production before changing settings or creating demo records' do
    user = create(:user)
    create(:review, user: user)
    create(:site_setting, lecture_review_restriction_enabled: true, last_updated_by: user)
    original_database = database_snapshot
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
    expect(SiteSetting).not_to receive(:current!)
    expect(ActiveRecord::Base).not_to receive(:transaction)

    expect do
      expect { task.invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/production/).to_stderr

    expect(database_snapshot).to eq(original_database)
  end

  %w[test development].each do |environment|
    it "prepares the existing demo records in #{environment}" do
      create(:site_setting, lecture_review_restriction_enabled: true)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(environment))

      expect { task.invoke }.to output(/review access demo data has been prepared/).to_stdout

      expect(SiteSetting.current.lecture_review_restriction_enabled).to be(false)
      expect(User.count).to eq(4)
      expect(Lecture.count).to eq(3)
      expect(Review.count).to eq(3)
      expect(User.find_by!(email: 'demo-review-access-locked@example.com').reviews_count).to eq(0)
      expect(User.find_by!(email: 'demo-review-access-unlocked@example.com').reviews_count).to eq(1)
    end
  end

  def database_snapshot
    [User, Lecture, Review, SiteSetting].to_h do |model|
      [model.name, model.order(:id).map(&:attributes)]
    end
  end
end
