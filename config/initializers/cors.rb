# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin AJAX requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    allowed_origins =
      if Rails.env.development?
        [
          'http://localhost:8080',
          'http://127.0.0.1:8080',
          'http://localhost:3000',
          'http://127.0.0.1:3000'
        ]
      elsif Rails.env.production?
        [
          ENV['FRONTEND_URL'],
          'https://www.gatareview.com',
          'https://gatareview.com',
          'https://gatareview-front.vercel.app',
          'https://gatareview.vercel.app'
        ].compact.uniq
      else
        ['http://localhost:8080']
      end

    origins(*allowed_origins)

    resource '*',
             headers: :any,
             methods: %i[get post put patch delete options head]
  end
end
