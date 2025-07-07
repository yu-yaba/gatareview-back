Rails.application.routes.draw do
  root to: 'site#index'

  namespace :api do
    namespace :v1 do
      # 認証関連のルート
      post '/auth/google', to: 'auth#google_oauth'
      get '/auth/me', to: 'auth#me'
      post '/auth/logout', to: 'auth#logout'

      get '/lectures/popular', to: 'lectures#popular'
      get '/lectures/no_reviews', to: 'lectures#no_reviews'
      resources :lectures do
        resources :reviews, only: %i[index create]
        resources :bookmarks, only: %i[create destroy show]
      end
      
      # レビュー関連のルート
      resources :reviews, only: %i[update destroy] do
        resources :thanks, only: %i[create destroy show]
      end
      get '/reviews/total', to: 'reviews#total'
      get '/reviews/latest', to: 'reviews#latest'
      
      # マイページ
      get '/mypage', to: 'mypage#show'
    end
  end

  get '*path', to: 'site#index', constraints: ->(request) { request.format.html? }
end
