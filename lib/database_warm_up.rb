# frozen_string_literal: true

# Puma の各ワーカーの起動時に、DB 接続を前もって用意する（config/puma.rb の before_worker_boot から呼ぶ）。
#
# 接続プールを「使用中」にしてから1本つなぐ。Rails は使用中のプールだけ、min_connections までの残りを
# reaper（約20秒ごと）が裏で作る（同じスレッドで1本つないだだけでは使用中にならない）。
# 先に使用中にしておき、失敗した接続は捨てるので、起動の瞬間に DB につながらなくても、DB が戻れば reaper が接続を作り直す。
#
# DB につながらなくてもワーカーは起動させる（例外は外に出さない）。原因が分かるように、
# 例外の種類とメッセージをログに出し、Sentry にも送る。
module DatabaseWarmUp
  def self.call(pool: ActiveRecord::Base.connection_pool, output: $stderr)
    pool.activate
    pool.with_connection(&:verify!)
    true
  rescue StandardError => e
    discard_unconnected(pool)
    output.puts '[puma] database warm-up failed; the pool will keep reconnecting in the background: ' \
                "#{e.class}: #{e.message}"
    Rails.error.report(e, handled: true, context: { source: 'puma_database_warm_up' })
    false
  end

  # つなぐのに失敗した接続はプールに残り、本数には数えられるが、Rails の定期処理はつなぎ直さない
  # （一度失敗した接続は preconnect の対象から外れる）。残すと、DB が戻っても裏でつながっている接続が1本足りない。
  # 使っていない接続を全部捨てる（プールは使用中のまま）と、定期処理が新しく2本作ってつなぐ。
  def self.discard_unconnected(pool)
    pool.flush(-1)
  rescue StandardError
    nil
  end
end
