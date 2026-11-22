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

  # 起動時に1本つなぎ、接続プールを「使用中」にする。Rails は使用中のプールだけ、min_connections までの
  # 残りを裏で作る（同じスレッドで1本つないだだけでは使用中にならない）。
  # 最初の利用者のリクエストが接続の準備（約1.5秒）を待たずに済む。
  # DB につながらなくてもワーカーは起動させ、リクエストのときに改めてつなぐ。
  begin
    pool = ActiveRecord::Base.connection_pool
    pool.with_connection(&:verify!)
    pool.activate
  rescue StandardError => e
    warn "[puma] database warm-up skipped: #{e.class}"
  end
end
