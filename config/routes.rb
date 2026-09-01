Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get    "login",  to: "sessions#new",     as: :login
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  get  "select_company", to: "sessions#select_company", as: :select_company
  post "choose_company", to: "sessions#choose_company", as: :choose_company

  resources :challenges, only: %i[index new create show] do
    member do
      get  :builder
      post :start
      post :close
    end

    # Pantalla de cada módulo del flujo. Despacha por kind.
    resources :steps, only: %i[show update] do
      member do
        post :advance
        post :skip
      end
      # La ficha de evaluación de una idea dentro de un módulo.
      resources :assessments, only: %i[new create]
      # Confirmar el corte y repescar ideas que quedaron fuera.
      resource :selection, only: %i[update] do
        post :reinstate
        post :verdict
      end
      resources :feedback_items, only: %i[create], path: "feedback" do
        member do
          post :resolve
          post :reopen
        end
      end
      resources :reports, only: %i[create] do
        collection { get :statuses }
      end
    end

    resources :ideas do
      member do
        post :submit
        get  :diff
      end
    end

    # Dispara una tarea de IA sobre este desafío (o uno de sus módulos/ideas).
    resources :ai_requests, only: %i[create]
  end

  # Mantenedor de criterios de la empresa.
  resources :criteria_sets do
    member { post :promote }
  end

  resources :ai_suggestions, only: [] do
    member do
      post :accept
      post :reject
    end
  end

  # Auditoría de la IA: qué se pidió, qué respondió, cuánto costó.
  resources :ai_runs, only: %i[index show], path: "admin/ai_runs"

  namespace :api do
    namespace :v1 do
      resources :challenges, only: [], param: :slug do
        # El builder lee y guarda el pipeline COMPLETO acá.
        resource :pipeline, only: %i[show update]
      end
    end
  end

  root "challenges#index"
end
