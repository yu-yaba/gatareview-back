Rails.application.routes.draw do
  root to: 'api/v2/lectures#index'

  namespace :api do
    namespace :v2 do 
      resources :lectures do
        resources :reviews, only: [:index, :create]
        member do
          post :images, to: 'lectures#create_image'
          get :images, to: 'lectures#show_image'
        end
      end
    end
  end

  get '*path', to: 'site#index', constraints: ->(request){ request.format.html? }
end
