# frozen_string_literal: true

module MysqlClientSecurity
  ConfigurationError = Class.new(StandardError)
  MINIMUM_CLIENT_ID = 80_413
  MAXIMUM_CLIENT_ID = 80_500

  module_function

  def validate!(client_info)
    id = client_info[:id]
    return if id.is_a?(Integer) && id >= MINIMUM_CLIENT_ID && id < MAXIMUM_CLIENT_ID

    raise ConfigurationError, 'Heroku requires the patched MySQL 8.4 client (8.4.13 or later)'
  end
end
