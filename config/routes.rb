Rails.application.routes.draw do
  root to: 'site#index'

  namespace :api do
    namespace :v1 do
      get '/lectures/popular', to: 'lectures#popular'
      get '/lectures/no_reviews', to: 'lectures#no_reviews'
      resources :lectures do
        resources :reviews, only: %i[index create]
      end
      get '/reviews/total', to: 'reviews#total'
      get '/reviews/latest', to: 'reviews#latest'
    end
  end

  get '*path', to: 'site#index', constraints: ->(request) { request.format.html? }
end
