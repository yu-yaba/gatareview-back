# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/mysql_client_security')
require 'digest'
require 'tmpdir'

RSpec.describe MysqlClientSecurity do
  it 'rejects the previously loaded client and malformed version metadata' do
    [80_411, 80_412, '80413', nil, 0, 101_100, 90_700].each do |id|
      expect { described_class.validate!(id: id) }.to raise_error(described_class::ConfigurationError)
    end
  end

  it 'accepts patched clients within the existing 8.4 ABI series' do
    [80_413, 80_414].each do |id|
      expect { described_class.validate!(id: id) }.not_to raise_error
    end
  end

  it 'rejects a tampered or missing native library before runtime startup' do
    Dir.mktmpdir('mysql-client-check') do |directory|
      FileUtils.mkdir_p(File.join(directory, 'config'))
      File.write(File.join(directory, 'client.so'), 'verified-test-client')
      expected = Digest::SHA256.hexdigest('verified-test-client')
      File.write(File.join(directory, 'config/mysql-client-files.sha256'), "#{expected}  client.so\n")
      command = Rails.root.join('bin/verify-mysql-client-files').to_s

      expect(system(command, directory, out: File::NULL, err: File::NULL)).to be(true)
      File.write(File.join(directory, 'client.so'), 'changed-test-client')
      expect(system(command, directory, out: File::NULL, err: File::NULL)).to be(false)
      File.delete(File.join(directory, 'client.so'))
      expect(system(command, directory, out: File::NULL, err: File::NULL)).to be(false)
    end
  end
end
