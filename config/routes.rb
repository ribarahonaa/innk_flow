Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get    "login",  to: "sessions#new",     as: :login
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  # El tema elegido a mano. Es una cookie y no una columna: el login es
  # público, así que una preferencia en `users` no serviría ahí; y es el
  # SERVIDOR el que la traduce a `data-theme`, con lo cual no hay parpadeo del
  # tema equivocado en la primera pintura y el morph no se lo puede llevar
  # —que es la misma familia del <details> que se cerraba solo—.
  resource :theme, only: :update

  # La ÚNICA ruta pública que escribe datos del dominio sin que nadie haya
  # probado quién es (el login también se sirve sin sesión, pero parte de alguien
  # que se autenticó con su clave; `up` no pasa por `ApplicationController`). Se
  # entra escaneando el QR de un taller, sin sesión y sin empresa en contexto —el
  # tenant sale del token—. Va acá y no colgada de `workshops` porque quien la
  # abre todavía no puede ver ningún taller.
  get  "checkin/:token", to: "workshop_checkins#show", as: :checkin
  post "checkin/:token", to: "workshop_checkins#create"

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
        # Pedirle a la IA que evalúe de una todo lo que le falta al módulo.
        post :evaluate_all
      end
      # Los criterios PROPIOS de este módulo, sin pasar por la biblioteca.
      resource :criteria, only: %i[show create], controller: "step_criteria"
      # La ficha de evaluación de una idea dentro de un módulo.
      resources :assessments, only: %i[new create]
      # El testeo de factibilidad de una idea dentro de un módulo.
      resources :step_tests, only: %i[new create]
      # Quién evalúa este módulo y cuánto pesa su voto.
      resources :step_assignments, only: %i[create update destroy], path: "evaluadores"
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
        # El archivo lo sirve la app, no Active Storage.
        member { get :download }
      end
    end

    resources :ideas do
      member do
        post :submit
        get  :diff
      end
      # Quiénes más participaron de la idea. Sin esto el criterio automático
      # "participan al menos N personas" no lo puede cumplir nadie.
      resources :contributors, only: %i[create destroy], controller: "idea_contributors"
      # El adjunto hereda la visibilidad de la idea, así que se baja por acá y
      # no por las rutas de Active Storage, que no preguntan nada.
      resources :attachments, only: %i[show], controller: "idea_attachments"
    end

    # Dispara una tarea de IA sobre este desafío (o uno de sus módulos/ideas).
    resources :ai_requests, only: %i[create]

    # Lo que van a ver las personas, antes de arrancar.
    resource :preview, only: %i[show], controller: "previews"

    # Quiénes acompañan la evolución de las ideas de ESTE desafío.
    resources :gestores, only: %i[create destroy], controller: "challenge_gestores"

    # El formulario de postulación del desafío (vive en su módulo de ideación).
    resource :form, only: %i[show], controller: "form_fields" do
      post :seed_defaults
    end
  end

  # El taller NO cuelga de un desafío: abarca varios. Por eso es de primer
  # nivel y no está anidado.
  resources :workshops, only: %i[index new create show update destroy] do
    member do
      post :open
      post :close
      # `to:` explícito: sin él, `post :convoke` mapea a `workshops#convoke`,
      # que no existe.
      post   :convoke, to: "workshop_convocations#create"
      delete :dismiss, to: "workshop_convocations#destroy"
      # Marcar presente o ausente. `to:` explícito por lo mismo que `convoke`:
      # sin él mapearía a `workshops#attendance`, que no existe.
      patch :attendance, to: "workshop_attendances#update"
      # Sacar un desafío del taller. El ciclo de vida lo pone junto a sumarlo,
      # o sea en borrador. El id del vínculo viaja como parámetro: no hay un
      # controller de vínculos, la baja es del taller.
      delete :remove_challenge
      # El check-in NO va por `workshops#update`, que es sólo de borrador:
      # activarlo tiene que poder hacerse con el taller ABIERTO, que es cuando
      # la gente está llegando.
      post :enable_checkin
      post :disable_checkin
      post :rotate_checkin_token
      # La mesa de llegada sola, para recargarla sin tocar el resto de la
      # pantalla. Es de LECTURA: por eso es GET y por eso no hay `to:` —mapea a
      # `workshops#arrival`, que sí existe—.
      get :arrival
    end
    resources :workshop_groups, only: %i[create destroy], path: "mesas" do
      post :assign, on: :collection
    end
    # La sala de UN desafío dentro del taller. El id es el del VÍNCULO, no el
    # del desafío: el vínculo es el que sabe contra qué módulo se trabaja.
    #
    # `show` es la pantalla donde la mesa trabaja: el formulario de idear o el
    # selector de ideas de evolución, con el brief del desafío y la mesa al
    # costado. `workshops#show` ya no apila las salas — es el selector.
    resources :workshop_challenges, only: %i[show], path: "salas", as: :sala,
                                    controller: "workshop_rooms" do
      resources :ideas, only: %i[create], controller: "workshop_ideas"
      resources :proposals, only: %i[create], controller: "workshop_proposals"
    end
  end

  # La propuesta se acepta desde la ficha de la idea, que es donde la ve su
  # autor: no cuelga del taller.
  resources :ideas, only: [] do
    resources :workshop_proposals, only: [], controller: "idea_workshop_proposals" do
      member do
        post :accept
        post :reject
      end
    end
  end

  # Quiénes están en la empresa y con qué rol.
  resources :members, only: %i[index create update destroy], controller: "memberships"

  # Mantenedor de criterios de la empresa.
  # Se escribe SOLO por la API que usa el editor: un set con nested attributes
  # por un lado y una isla por el otro serían dos caminos y una laguna.
  #
  # Sin `destroy` A PROPÓSITO: la interfaz nunca ofreció borrar un set, y una
  # ruta sin pantalla es una capacidad del dominio sin interfaz (mismo criterio
  # con el que se borró `Tasks::EvaluateIdea#editable?`). Si hace falta, se
  # vuelve a agregar; el modelo ya se niega a borrar un set que usa un módulo.
  resources :criteria_sets, only: %i[index new show edit] do
    member { post :promote }
  end

  # La bandeja de avisos.
  resources :notifications, only: %i[index show] do
    collection { post :read_all }
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
