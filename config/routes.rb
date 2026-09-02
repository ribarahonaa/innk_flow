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
      # Arma el flujo desde una plantilla. Solo sobre un desafío sin módulos.
      post :apply_template
    end

    # Pantalla de cada módulo del flujo. Despacha por kind.
    resources :steps, only: %i[show update] do
      member do
        post :advance
        post :skip
      end
      # Los criterios PROPIOS de este módulo, sin pasar por la biblioteca.
      resource :criteria, only: %i[show create], controller: "step_criteria"
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

    # Lo que van a ver las personas, antes de arrancar.
    resource :preview, only: %i[show], controller: "previews"

    # El formulario de postulación del desafío (vive en su módulo de ideación).
    resource :form, only: %i[show], controller: "form_fields" do
      post :seed_defaults
    end
  end

  # Mantenedor de criterios de la empresa.
  # Se escribe SOLO por la API que usa el editor: un set con nested attributes
  # por un lado y una isla por el otro serían dos caminos y una laguna.
  resources :criteria_sets, only: %i[index new show edit destroy] do
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
        resource :form_fields, only: %i[show update], path: "form"
      end

      # El editor de criterios guarda el set COMPLETO acá.
      resources :criteria_sets, only: %i[create update]
    end
  end

  root "challenges#index"
end
