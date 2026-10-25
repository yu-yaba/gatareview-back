# frozen_string_literal: true

require Rails.root.join('lib/mysql_client_security')

if Rails.env.production? && ENV['DYNO'].present?
  client_info = Mysql2::Client.info
  MysqlClientSecurity.validate!(client_info)
  Rails.logger.info("MySQL client runtime: #{client_info[:version]} (headers #{client_info[:header_version]})")
end
