# frozen_string_literal: true

module DatabaseTlsConfiguration
  class ConfigurationError < StandardError; end

  module_function

  def validate!(configuration)
    mode = configuration[:ssl_mode].to_s.downcase.delete_prefix('ssl_mode_')
    raise ConfigurationError, 'Production MySQL requires ssl_mode=verify_identity' unless mode == 'verify_identity'

    ca_path = configuration[:sslca]
    return if ca_path.blank?
    return if File.file?(ca_path) && File.readable?(ca_path)

    raise ConfigurationError, 'MYSQL_SSL_CA must point to a readable CA certificate file'
  end
end
