Rails.application.routes.draw do

  get "music/index"
  devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)
  get "voice/index"
  # get "features/index"
  # get "uploaded_files/index"
  # get "uploaded_files/create"
  # get "uploaded_files/destroy"
  # get "payor_preferences/index"
  # get "payor_preferences/show"
  # get "validations/index"
  # get "validations/upload"
  # get "payors/index"
  # get "payors/upload"
  # get "payment_factors/index"
  # get "payment_factors/upload"
  # get "og/index"
  # get "og/upload"
  # get "documents/index"
  # get "documents/new"
  # get "documents/create"
  # get "documents/show"
  
  resources :pricing_catalogs, only: [:index, :create] do
    collection do
      get :mapping
      post :process_mapping
      get :results
      get :download
    end
  end

  resources :schema_visualizers, only: [ :index, :create ]
  
  resources :file_conversions, only: [:index] do
    collection do
      post :convert
    end
  end

  get '/visualizer', to: 'visualizers#index', as: :visualizer
  post '/visualizer/evaluate', to: 'visualizers#evaluate', as: :visualizer_evaluate
  # get "sheets/index"
  # get "sheets/upload"
  # root "students#index"
  root "home#index"
  get "home", to: "home#index", as: :home
  # --- Authentication Routes ---
  get "signup" => "users#new"
  post "signup" => "users#create"

  get "login" => "sessions#new"
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy"

  # Console routes
  get 'console', to: 'console#execute'
  post 'console/execute', to: 'console#execute'

  get  "students"        => "students#index", as: :students
  post "students/upload" => "students#upload", as: :upload_students

  get "sheets"           => "sheets#index", as: :sheets
  post "sheets/upload"   => "sheets#upload", as: :upload_sheets

  get "og"               => "og#index", as: :og
  post "og/upload"       => "og#upload", as: :upload_og

  get "payment_factors"  => "payment_factors#index", as: :payment_factors
  post "payment_factors/upload" => "payment_factors#upload", as: :upload_payment_factors

  get "payors"           => "payors#index", as: :payors
  post "payors/upload"   => "payors#upload", as: :upload_payors

  get "validations"      => "validations#index", as: :validations
  post "validations/upload"=>"validations#upload", as: :upload_validations

  get "payor_preferences" => "payor_preferences#index", as: :payor_preferences
  get "payor_preferences/strengths" => "payor_preferences#strengths"
  get "payor_preferences/:id" => "payor_preferences#show", as: :payor_preference

  get "uploaded_files" => "uploaded_files#index", as: :uploaded_files
  post "uploaded_files" => "uploaded_files#create"
  delete "uploaded_files/:id" => "uploaded_files#destroy", as: :uploaded_file
  post "uploaded_files/delete_with_password",
     to: "uploaded_files#delete_with_password",
     as: :delete_with_password_uploaded_file

  get "features" => "features#index", as: :features
  post "features/run_automation" => "features#run_automation", as: :run_automation
  get "automations" => "automations#index", as: :automations
  get "auto_validation" => "auto_validations#index", as: :auto_validation
  get "auto_validation/results" => "auto_validations#results", as: :auto_validation_results
  get "auto_ranking" => "auto_rankings#index", as: :auto_ranking
  get "auto_ranking/results" => "auto_rankings#results", as: :auto_ranking_results
  get "voice" => "voice_queries#index", as: :voice
  # post "/voice/query", to: "voice_queries#create", as: :voice_query
  post "voice_queries/create", to: "voice_queries#create"

  get "voice_query_logs" => "voice_query_logs#index", as: :voice_query_logs

  get "music" => "music#index", as: :music


  get "biosimilar_prices"               => "biosimilar_prices#index", as: :biosimilar_prices
  post "biosimilar_prices/upload"       => "biosimilar_prices#upload", as: :upload_biosimilar_prices
  resources :gmail_extractions, only: [ :index, :show, :create ]
  resources :screen_analyses, only: [ :index, :show, :new, :create, :destroy ]
  resources :new_biosimilar_prices do
    collection do
      get  :upload_blended_costs
      post :import_blended_costs
    end
  end
  resources :quarter_statuses, only: [:index]
  resources :insurance_factors
  resources :product_preference_records, only: [ :new, :create, :index, :show ]
  resources :ranking_records, only: [ :new, :create, :index, :show ] do
    collection do
      post :lookup_insurances
    end
  end
  resources :product_rankings, only: [:index]
  resources :tally_validations, only: [:index] do
    collection do
      post :upload
      delete :clear_history
    end
  end

  resources :insurance_preference_validations, only: [:index, :create, :show, :destroy] do
    member do
      get :download
      get :results
    end
  end

  resources :brand_insurance_mappings, only: [:index, :create, :show] do
    member do
      get :download
    end
    collection do
      delete :clear_history
    end
  end


  resources :alert_emails, only: [:index, :create, :destroy] do
    collection do
      post :validate_and_trigger
    end
  end
  
  resources :automation_schedules, only: [:index, :show, :create, :destroy]
  # Google OAuth (Gmail)
  get "/auth/google_oauth2/callback", to: "gmail_oauth#callback"

  # GitHub OAuth
  get "/auth/github/callback", to: "github#callback"
  get "/auth/failure", to: "oauth#failure"
  # index
  get "/github", to: "github#index", as: :github

  # Dashboard
  get "/github/dashboard", to: "github#dashboard", as: :github_dashboard

  # Refresh data
  post "/github/refresh", to: "github#refresh", as: :github_refresh

  namespace :api do
    # post 'auto_validate', to: 'validations#auto_validate'
    match 'auto_validate', to: 'validations#auto_validate', via: [:get, :post]
    match 'auto_rankings/validate', to: 'auto_rankings#validate', via: [:get, :post]
  end
end
