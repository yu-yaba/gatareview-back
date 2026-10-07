# frozen_string_literal: true

require Rails.root.join('lib/database_tls_configuration')

if Rails.env.production?
  ActiveRecord::Base.configurations.configs_for(env_name: 'production').each do |configuration|
    DatabaseTlsConfiguration.validate!(configuration.configuration_hash)
  end
end
