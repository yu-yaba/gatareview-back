# frozen_string_literal: true

# MySQL がデッドロックで巻き戻した書き込みを、1回だけやり直す。
#
# デッドロック時は MySQL がトランザクション全体を巻き戻すため、やり直してよいのは
# ブロックの外側に（合流できる）トランザクションがないときだけ。外側にある場合は
# そのまま例外を上げ、呼び出し元に任せる。テストのトランザクションは合流できない
# 扱いなので、テストでもやり直しを確認できる。
module DeadlockRetry
  MAX_RETRIES = 1

  def self.call
    retries = 0
    begin
      yield
    rescue ActiveRecord::Deadlocked
      raise if retries >= MAX_RETRIES || inside_joinable_transaction?

      retries += 1
      Rails.logger.warn('Retrying a write after a database deadlock')
      retry
    end
  end

  def self.inside_joinable_transaction?
    ActiveRecord::Base.lease_connection.current_transaction.joinable?
  end
  private_class_method :inside_joinable_transaction?
end
