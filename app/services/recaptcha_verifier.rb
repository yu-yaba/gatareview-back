# frozen_string_literal: true

require 'httparty'

class RecaptchaVerifier
  DEFAULT_ALLOWED_HOSTNAMES = %w[gatareview.com www.gatareview.com].freeze

  attr_reader :score, :action, :hostname

  def initialize(token, expected_action = 'submit', minimum_score = 0.5, remote_ip: nil, allowed_hostnames: self.class.allowed_hostnames)
    @token = token
    @expected_action = expected_action
    @minimum_score = minimum_score
    @remote_ip = remote_ip
    @allowed_hostnames = allowed_hostnames.map { |hostname| hostname.to_s.strip.downcase }.reject(&:blank?)
    @score = 0.0
    @action = ''
    @hostname = ''
  end

  def self.allowed_hostnames
    configured = ENV.fetch('RECAPTCHA_ALLOWED_HOSTNAMES', '').split(',').map(&:strip).reject(&:blank?)
    configured.presence || DEFAULT_ALLOWED_HOSTNAMES
  end

  def verify
    secret_key = ENV['RECAPTCHA_SECRET_KEY']
    return false if secret_key.blank?

    body = {
      secret: secret_key,
      response: @token
    }
    body[:remoteip] = @remote_ip if @remote_ip.present?

    response = HTTParty.post(
      'https://www.google.com/recaptcha/api/siteverify',
      body: body
    )

    result = JSON.parse(response.body)

    if valid_result?(result)
      @score = result['score']
      @action = result['action']
      @hostname = result['hostname']
      true
    else
      false
    end
  rescue StandardError => e
    Rails.logger.error "reCAPTCHA verification failed: #{e.message}"
    false
  end

  private

  def valid_result?(result)
    result['success'] &&
      result['action'] == @expected_action &&
      result['score'].to_f >= @minimum_score &&
      @allowed_hostnames.include?(result['hostname'].to_s.downcase)
  end
end
