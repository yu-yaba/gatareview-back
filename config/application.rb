require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module App
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins 'http://localhost:8080' # フロントエンドのオリジン
        resource '*',
                 headers: :any,
                 methods: %i[get post put patch delete options head]
      end
    end

    # lib配下もオートロード対象にする
    config.autoload_paths += %W[#{config.root}/lib]
    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Rails 7.0の新しい接続処理を使用
    config.active_record.legacy_connection_handling = false

    config.generators do |g|
      g.test_framework :rspec
    end
  end
end
