# frozen_string_literal: true

# 本番の DB 接続が、証明書とホスト名の両方を検証する TLS になっているかを起動時に確かめる。
#
# DATABASE_URL の sslmode は config/database.yml の sslmode より優先される。Aiven の接続 URI は
# sslmode=require（暗号化するが証明書を検証しない）を含むため、そのまま貼ると検証が弱まる。
# その場合は起動を止め、URL の sslmode を外すか verify-full にするよう知らせる。
module DatabaseTlsConfiguration
  class ConfigurationError < StandardError; end

  module_function

  def validate!(configuration)
    mode = configuration[:sslmode].to_s
    unless mode == 'verify-full'
      raise ConfigurationError,
            "Production PostgreSQL requires sslmode=verify-full (got #{mode.inspect}). " \
            'Remove sslmode from DATABASE_URL or set it to verify-full.'
    end

    # pg gem の同梱 libpq は sslrootcert=system でも OS の CA ストアを読まないので、
    # CA 証明書のファイルを必ず指定させる（指定がないと全接続が証明書エラーになる）。
    ca_path = configuration[:sslrootcert].to_s
    return if ca_path != 'system' && File.file?(ca_path) && File.readable?(ca_path)

    raise ConfigurationError, 'DATABASE_SSL_CA must point to a readable CA certificate file'
  end
end
