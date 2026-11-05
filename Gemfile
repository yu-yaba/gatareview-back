# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.4.12'

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem 'rails', '~> 8.1.4', '>= 8.1.4.1'

# Use mysql as the database for Active Record
# gem "mysql2", "~> 0.5"

# Use the Puma web server [https://github.com/puma/puma]
gem 'puma', '~> 8.0'

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

gem 'httparty'

# Error monitoring; enabled only when a production DSN is configured.
gem 'sentry-rails', '~> 7.2'
gem 'sentry-ruby', '~> 7.2'

gem 'dotenv-rails', groups: %i[development test]

gem 'recaptcha', require: 'recaptcha/rails'
# Use Redis adapter to run Action Cable in production
# gem "redis", "~> 4.0"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# JWT authentication
gem 'jwt'

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
gem 'rack-cors'

# Throttle abuse-prone public endpoints before they exhaust application threads.
gem 'rack-attack'

gem 'kaminari'

gem 'pry-rails'

gem 'mysql2', '~> 0.5.6'

gem 'rspec-rails'

# Keep CI lint behavior stable during the Rails upgrade.
gem 'rubocop', '1.92.2', require: false

gem 'factory_bot_rails'

gem 'faker'

gem 'activerecord-import'

group :development do
  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
  gem 'debug', platforms: %i[mri mingw x64_mingw]

  gem 'solargraph'
end

group :test do
end

# group :production do
#   gem 'pg', '~> 1.2', '>= 1.2.3'
# end
