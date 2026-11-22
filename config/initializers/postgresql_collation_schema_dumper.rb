# frozen_string_literal: true

# Rails の schema.rb は独自に作った照合順序（CREATE COLLATION）を書き出さない。
# 書き出さないと db:schema:load やテスト DB の作り直しで「collation "ci_ai" does not exist」になるため、
# public スキーマにある ICU の照合順序を schema.rb の先頭に出力する。
module PostgresqlCollationSchemaDumper
  COLLATIONS_SQL = <<~SQL.squish
    SELECT collname, colllocale, collisdeterministic
    FROM pg_collation
    WHERE collnamespace = 'public'::regnamespace AND collprovider = 'i'
    ORDER BY collname
  SQL

  private

  def extensions(stream)
    super
    collations = @connection.select_rows(COLLATIONS_SQL)
    return if collations.empty?

    stream.puts '  # Custom collations (config/initializers/postgresql_collation_schema_dumper.rb)'
    collations.each do |name, locale, deterministic|
      sql = "CREATE COLLATION IF NOT EXISTS #{@connection.quote_column_name(name)} " \
            "(provider = icu, locale = #{@connection.quote(locale)}, deterministic = #{deterministic})"
      stream.puts "  execute #{sql.inspect}"
    end
    stream.puts
  end
end

ActiveSupport.on_load(:active_record_postgresqladapter) do
  ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper.prepend(PostgresqlCollationSchemaDumper)
end
