Rails.application.routes.draw do
  root to: 'site#index'

  namespace :api do
    namespace :v1 do
      resources :lectures do
        resources :reviews, only: %i[index create]
      end
      get '/reviews/total', to: 'reviews#total'
    end
  end

  get '*path', to: 'site#index', constraints: ->(request) { request.format.html? }
end
