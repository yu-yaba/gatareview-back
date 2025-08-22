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
        # カスタムブックマークルート
        post 'bookmarks', to: 'bookmarks#create'
        get 'bookmarks', to: 'bookmarks#show'
        delete 'bookmarks', to: 'bookmarks#destroy'
      end
      
      # レビュー関連のルート
      resources :reviews, only: %i[update destroy] do
        # カスタムありがとうルート
        post 'thanks', to: 'thanks#create'
        get 'thanks', to: 'thanks#show'
        delete 'thanks', to: 'thanks#destroy'
      end
      get '/reviews/total', to: 'reviews#total'
      get '/reviews/latest', to: 'reviews#latest'
      
      # レビュー期間管理
      resources :review_periods do
        member do
          patch :activate
          patch :deactivate
        end
        collection do
          get :current
        end
      end
      
      # マイページ
      get '/mypage', to: 'mypage#show'
      get '/mypage/reviews', to: 'mypage#reviews'
      get '/mypage/bookmarks', to: 'mypage#bookmarks'
    end
  end

  get '*path', to: 'site#index', constraints: ->(request) { request.format.html? }
end
