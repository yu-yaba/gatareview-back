require_relative 'web_concurrency'

workers WebConcurrency.workers
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 5)
threads threads_count, threads_count

preload_app!

rackup      DefaultRackup if defined?(DefaultRackup)
port        ENV['PORT']     || 3000
environment ENV['RACK_ENV'] || 'development'

before_worker_boot do
  # Worker specific setup for Rails 4.1+
  # See: https://devcenter.heroku.com/articles/deploying-rails-applications-with-the-puma-web-server#on-worker-boot
  ActiveRecord::Base.establish_connection

  # 接続プールを使用中にして1本つなぎ、最初の利用者のリクエストが接続の準備（約1.5秒）を待たずに済むようにする。
  # 仕組みと、DB につながらなかったときの扱いは lib/database_warm_up.rb。
  require_relative '../lib/database_warm_up'
  DatabaseWarmUp.call
end
