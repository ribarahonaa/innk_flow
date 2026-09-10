# frozen_string_literal: true

require "rails_helper"

# Los criterios de un módulo, definidos sin salir del desafío.
#
# El modelo ya soportaba sets `inline` —atados a un módulo— pero nada los
# creaba salvo el propio handler AL ACTIVAR, cuando su dueño ya no los ve
# venir. El único camino visible era la biblioteca.
RSpec.describe "criterios de un módulo", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:owner) do
    without_tenant do
      u = create(:user, email: "owner@test.dev")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma")
      seed_form!(c.steps.create!(kind: "ideation", position: 1, name: "Postulación"))
      c.steps.create!(kind: "evaluation", position: 2, name: "Técnica")
      c
    end
  end

  def step = as_company(company) { challenge.steps.reload.find(&:evaluation?) }
  def criteria_path = challenge_step_criteria_path(challenge, step)
  def set_of(a_step) = as_company(company) { ChallengeStep.find(a_step.id).criteria_set }
  def criteria_of(a_step) = as_company(company) { ChallengeStep.find(a_step.id).criteria_set.criteria.ordered.to_a }

  before { sign_in(owner, company: company) }

  # La pantalla propia de criterios se borró: el editor vive embebido en la
  # cara de configuración del módulo (`StepsController#show`, cuando el
  # módulo está pendiente). La URL vieja se conserva como redirect, no como
  # 404, porque vive en links, marcadores y `back_url`.
  describe "la pantalla vieja de criterios" do
    it "redirige a la pantalla del módulo" do
      get criteria_path

      expect(response).to redirect_to(challenge_step_path(challenge, step))
    end
  end

  describe "cuando el módulo no tiene criterios propios" do
    it "dice con qué va a correr y ofrece las salidas" do
      get challenge_step_path(challenge, step)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("todavía no tiene criterios propios",
                                       "Usar los tres genéricos y editarlos",
                                       "Empezar en blanco")
    end

    it "«los tres genéricos» los crea atados a ESTE módulo" do
      post criteria_path, params: { from: "defaults" }

      set = set_of(step)
      expect(set.scope).to eq("inline")
      expect(as_company(company) { set.owner_step_id }).to eq(step.id)
      expect(criteria_of(step).map(&:key)).to eq(%w[impacto factibilidad esfuerzo])
    end

    it "«en blanco» crea el set vacío, para armarlo desde cero" do
      post criteria_path, params: { from: "blank" }

      expect(criteria_of(step)).to be_empty
      expect(set_of(step).status).to eq("invalid")
    end

    it "y después de crearlos, monta el editor" do
      post criteria_path, params: { from: "defaults" }
      get challenge_step_path(challenge, step)

      expect(response.body).to include('data-island="criteria-editor"')
      expect(response.body).to include("no afectan a otros desafíos")
    end
  end

  describe "cuando el módulo apunta a un set de la biblioteca" do
    let!(:library) do
      as_company(company) do
        s = CriteriaSet.create!(name: "Estándar", scope: "library")
        s.criteria.create!(name: "Impacto", key: "impacto", weight: 1, source: "manual",
                           scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 })
        s.refresh_status!
        s
      end
    end

    before { as_company(company) { ChallengeStep.find(step.id).update!(criteria_set_id: library.id) } }

    # Editar el set de la biblioteca desde el módulo tocaría a todos los
    # desafíos que lo comparten. Se copia, no se apunta.
    it "no deja editarlo desde acá: ofrece copiarlo" do
      get challenge_step_path(challenge, step)

      expect(response.body).to include("Estándar", "Copiar ese set y hacerlo propio")
      expect(response.body).not_to include('data-island="criteria-editor"')
    end

    it "copiar deja la biblioteca intacta" do
      post criteria_path, params: { from: "library" }

      copy = set_of(step)
      expect(copy.id).not_to eq(library.id)
      expect(copy.scope).to eq("inline")
      expect(criteria_of(step).map(&:key)).to eq(%w[impacto])
      expect(as_company(company) { CriteriaSet.library.pluck(:name) }).to eq(["Estándar"])
    end
  end

  # Las dos capacidades de biblioteca que el panel del builder se llevó puestas
  # al borrarse (`step_config.vue`, `58bd076`): apuntar el módulo a un set
  # compartido, y pasarlo a la versión siguiente cuando la biblioteca se
  # versionó. Sin ellas nada escribía `criteria_set_id` apuntando a la
  # biblioteca —el único escritor era la COPIA `inline` de acá al lado— y dos
  # avisos de la app («podés elegir un set de la biblioteca» en
  # `Flow::Pipeline#validate`, «asignales la nueva desde su módulo» en
  # `CriteriaSetPresenter`) pedían algo que no tenía cómo hacerse.
  describe "elegir un set de la biblioteca" do
    let!(:library) do
      as_company(company) do
        s = CriteriaSet.create!(name: "Estándar", scope: "library")
        s.criteria.create!(name: "Impacto", key: "impacto", weight: 1, source: "manual",
                           scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 })
        s.refresh_status!
        s
      end
    end

    # Cuenta la anidación de <form> en el HTML SERVIDO. En el DOM no se puede
    # mirar: el navegador descarta el form interno al parsear y sus botones
    # pasan a pertenecer al externo. El bloque de criterios sirve varios
    # `button_to` —o sea, varios forms— al lado del nuevo select.
    def profundidad_maxima_de_forms(html)
      maxima = 0
      actual = 0
      html.scan(%r{<form\b|</form>}) do |etiqueta|
        actual += etiqueta == "</form>" ? -1 : 1
        maxima = [maxima, actual].max
      end
      maxima
    end

    it "la cara de configuración ofrece elegirlo" do
      get challenge_step_path(challenge, step)

      expect(response.body).to include('name="challenge_step[criteria_set_id]"')
      expect(response.body).to include("Estándar")
    end

    it "no sirve un formulario dentro de otro" do
      get challenge_step_path(challenge, step)

      expect(profundidad_maxima_de_forms(response.body)).to eq(1)
    end

    # Un solo camino de escritura para la configuración del módulo: el PATCH
    # de `steps#update`. Nada de un endpoint nuevo para esto.
    it "asignarlo va por el PATCH del módulo" do
      patch challenge_step_path(challenge, step),
            params: { challenge_step: { criteria_set_id: library.id } }

      expect(response).to redirect_to(challenge_step_path(challenge, step))
      expect(set_of(step)&.id).to eq(library.id)
    end

    it "y se puede volver a los genéricos dejándolo en blanco" do
      as_company(company) { ChallengeStep.find(step.id).update!(criteria_set_id: library.id) }

      patch challenge_step_path(challenge, step),
            params: { challenge_step: { criteria_set_id: "" } }

      expect(set_of(step)).to be_nil
    end

    it "quien no configura no recibe el control" do
      participante = without_tenant do
        u = create(:user, email: "part-criterios@test.dev", name: "Paula Participante")
        create(:membership, company: company, user: u, role: "participant")
        u
      end
      sign_in(participante, company: company)

      get challenge_step_path(challenge, step)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('name="challenge_step[criteria_set_id]"')
    end

    describe "cuando la biblioteca se versiona bajo los pies del módulo" do
      let!(:nueva) do
        as_company(company) do
          ChallengeStep.find(step.id).update!(criteria_set_id: library.id)
          CriteriaSet.find(library.id).next_version!
        end
      end

      it "el módulo avisa que hay una más nueva y ofrece pasarlo" do
        get challenge_step_path(challenge, step)

        expect(response.body).to include("Hay una versión más nueva")
        expect(response.body).to include("Pasarlo a")
      end

      # El botón es un `button_to` con `params:` anidado: si Rails no armara el
      # hidden con el nombre anidado, el PATCH llegaría sin nada que cambiar y
      # el botón sería otro control que no responde. Se mira el form SERVIDO.
      it "el botón manda el id de la nueva en el nombre que espera el controller" do
        get challenge_step_path(challenge, step)

        formulario = response.body.scan(%r{<form\b.*?</form>}m).find { |f| f.include?("Pasarlo a") }

        expect(formulario).to be_present
        expect(formulario).to include(%(name="challenge_step[criteria_set_id]"))
        expect(formulario).to include(%(value="#{nueva.id}"))
      end

      it "pasarlo lo deja en la vigente, sin tocar la anterior" do
        patch challenge_step_path(challenge, step),
              params: { challenge_step: { criteria_set_id: nueva.id } }

        expect(set_of(step)&.id).to eq(nueva.id)
        expect(as_company(company) { CriteriaSet.find(library.id) }).to be_superseded
      end
    end

    # `criteria_set_id` está en `FROZEN_ATTRIBUTES`: con el módulo arrancado,
    # cambiar de set reescribiría la vara con la que ya se puntuó.
    describe "con el módulo ya arrancado" do
      before do
        as_company(company) do
          ChallengeStep.find(step.id).update!(criteria_set_id: library.id)
          Flow::Handlers::Base.for(ChallengeStep.find(step.id)).activate!
        end
      end

      it "la pantalla ya no es la de configuración: no hay ningún control" do
        get challenge_step_path(challenge, step)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('name="challenge_step[criteria_set_id]"')
        expect(response.body).not_to include("Hay una versión más nueva")
      end

      it "y el PATCH tampoco lo cambia" do
        otro = as_company(company) { CriteriaSet.create!(name: "Otro", scope: "library") }

        patch challenge_step_path(challenge, step),
              params: { challenge_step: { criteria_set_id: otro.id } }

        expect(flash[:alert]).to include("ya ejecutado")
        expect(set_of(step)&.id).to eq(library.id)
      end
    end
  end

  describe "con el módulo ya ejecutado" do
    before { as_company(company) { ChallengeStep.find(step.id).update_column(:status, "completed") } }

    it "no se crean criterios nuevos: quedaron congelados" do
      post criteria_path, params: { from: "defaults" }

      expect(flash[:alert]).to include("ya se ejecutó")
      expect(set_of(step)).to be_nil
    end
  end

  # Un criterio de fórmula guarda el resultado crudo porque de ahí sale la
  # normalización. Mostrarlo entero en la ficha no le dice nada a nadie.
  describe "cómo se muestra un puntaje derivado" do
    it "redondea el resultado de una fórmula, y deja los enteros enteros" do
      # `.new` ya toca el default_scope, así que también va dentro del tenant.
      as_company(company) do
        score = AssessmentScore.new(criterion_key: "prioridad", raw_value: "1.1428571428571428571",
                                    numeric_value: BigDecimal("1.1428571428571428571"))
        expect(score.display_value).to eq("1.14")

        entero = AssessmentScore.new(criterion_key: "impacto", raw_value: "8", numeric_value: 8)
        expect(entero.display_value).to eq("8")

        vacio = AssessmentScore.new(criterion_key: "impacto", raw_value: nil)
        expect(vacio.display_value).to eq("—")
      end
    end
  end

  # Los criterios cuelgan de un módulo, así que redirigir por tipo de objetivo
  # sacaba de la pantalla de criterios justo al aplicarlos.
  describe "proponer los criterios con IA" do
    it "la pantalla lo ofrece cuando el módulo no tiene criterios propios" do
      get challenge_step_path(challenge, step)
      expect(response.body).to include("Proponer criterios con IA")
    end

    # El destino es la pantalla del MÓDULO, no `criteria_path`: esa URL sólo
    # redirige ahí desde que el editor se embebió. Apuntar `accept` a la
    # vieja encadenaba un 302 → 301 de más para llegar al mismo lugar.
    it "aplicar la propuesta deja en la pantalla del módulo, con el set puesto" do
      post challenge_ai_requests_path(challenge, purpose: "suggest_criteria", step_id: step.id)
      sugerencia = as_company(company) { AiSuggestion.pending_review.order(:created_at).last }

      post accept_ai_suggestion_path(sugerencia)

      expect(response).to redirect_to(challenge_step_path(challenge, step))
      expect(set_of(step)&.scope).to eq("inline")
      expect(criteria_of(step)).not_to be_empty
    end
  end

  describe "dónde no aplica" do
    it "un módulo de ideación no tiene criterios: 404" do
      ideation = as_company(company) { challenge.steps.reload.find(&:ideation?) }
      get challenge_step_criteria_path(challenge, ideation)

      expect(response).to have_http_status(:not_found)
    end
  end
end
