# frozen_string_literal: true

require 'httparty'

class RecaptchaVerifier
  RECAPTCHA_SECRET_KEY = ENV['RECAPTCHA_SECRET_KEY']

  attr_reader :score, :action

  def initialize(token, expected_action = 'submit', minimum_score = 0.5)
    @token = token
    @expected_action = expected_action
    @minimum_score = minimum_score
    @score = 0.0
    @action = ''
  end

  def verify
    response = HTTParty.post(
      "https://www.google.com/recaptcha/api/siteverify",
      body: {
        secret: RECAPTCHA_SECRET_KEY,
        response: @token
      }
    )

    result = JSON.parse(response.body)

    if result['success'] && result['action'] == @expected_action && result['score'] >= @minimum_score
      @score = result['score']
      @action = result['action']
      true
    else
      false
    end
  rescue StandardError => e
    Rails.logger.error "reCAPTCHA verification failed: #{e.message}"
    false
  end
end
