# frozen_string_literal: true

require "rails_helper"

# El formulario de postulación: quién lo define, dónde, y hasta cuándo.
#
# Antes se sembraba solo al activar el módulo. El dueño del desafío no veía
# nunca sus propias preguntas: nacían con el desafío ya corriendo, cuando la
# ventana para cambiarlas ya se había cerrado.
RSpec.describe "formulario de postulación", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  let!(:owner) do
    without_tenant do
      u = create(:user, email: "owner@test.dev")
      create(:membership, :owner, company: company, user: u)
      u
    end
  end

  let!(:participant) do
    without_tenant do
      u = create(:user, email: "part@test.dev")
      create(:membership, company: company, user: u)
      u
    end
  end

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma en bodega")
      c.steps.create!(kind: "ideation", position: 1, name: "Postulación")
      c
    end
  end

  def step = as_company(company) { challenge.steps.reload.find(&:ideation?) }
  def fields = as_company(company) { step.form_fields.ordered.to_a }
  def api_path = "/api/v1/challenges/#{challenge.slug}/form"
  def json = JSON.parse(response.body)

  # El editor vive embebido en la pantalla del módulo de idear
  # (`StepsController#show`): la URL propia de acá abajo se borró y
  # `challenge_form_path` quedó como redirect (ver "la pantalla vieja").
  describe "la pantalla" do
    before { sign_in(owner, company: company) }

    it "con el módulo vacío, dice que nadie puede postular y ofrece las dos salidas" do
      get challenge_step_path(challenge, step)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Todavía no hay campos", "Usar los tres básicos",
                                       "Proponer campos con IA")
    end

    it "monta el editor con las props serializadas por el server" do
      as_company(company) { seed_form!(step) }

      get challenge_step_path(challenge, step)

      expect(response.body).to include('data-island="form-editor"')
      expect(response.body).to include("¿Qué problema resuelve?")
    end

    it "«Usar los tres básicos» los crea de una" do
      post seed_defaults_challenge_form_path(challenge)

      expect(fields.map(&:key)).to eq(%w[titulo problema solucion])
      expect(fields.first.title?).to be(true)
    end

    it "no los siembra dos veces" do
      post seed_defaults_challenge_form_path(challenge)
      post seed_defaults_challenge_form_path(challenge)

      expect(fields.size).to eq(3)
      expect(flash[:alert]).to include("ya tiene campos")
    end
  end

  # El formulario se editaba en una pantalla propia. Esta URL vivía en links,
  # marcadores y `back_url`, así que redirige en vez de dar 404.
  describe "la pantalla vieja del formulario" do
    it "redirige a la pantalla del módulo" do
      sign_in(owner, company: company)
      get challenge_form_path(challenge)

      expect(response).to redirect_to(challenge_step_path(challenge, step))
    end

    # `show?`, no `manage_form?`: el destino es la pantalla del módulo, que
    # cualquiera de la empresa puede ver. Pedir un permiso más estricto que el
    # del destino le daba 403 a un marcador viejo de alguien que sí puede ver
    # a dónde lo manda.
    it "quien participa también sigue el redirect: el candado vive en la pantalla del módulo" do
      sign_in(participant, company: company)
      get challenge_form_path(challenge)

      expect(response).to redirect_to(challenge_step_path(challenge, step))
    end
  end

  # El panel de propuestas vivía en la rama «ya hay campos» del if. Pedir la
  # propuesta con el formulario VACÍO —el caso más común— la dejaba invisible:
  # aparecía solo en la pantalla del módulo.
  describe "la propuesta de la IA" do
    before { sign_in(owner, company: company) }

    def proponer
      post challenge_ai_requests_path(challenge, purpose: "suggest_form_fields", step_id: step.id)
    end

    it "se ve en el formulario aunque todavía no haya campos" do
      proponer

      get challenge_step_path(challenge, step)
      expect(response.body).to include("Propuestas de la IA")
    end

    it "y también cuando ya hay campos" do
      as_company(company) { seed_form!(step) }
      proponer

      get challenge_step_path(challenge, step)
      expect(response.body).to include("Propuestas de la IA")
    end

    # El destino es la pantalla del MÓDULO, no `challenge_form_path`: esa URL
    # sólo redirige ahí desde que el editor se embebió (Task 7). Apuntar
    # `accept` a la vieja encadenaba un 302 → 301 de más para llegar al mismo
    # lugar.
    it "aplicarla te deja en la pantalla del módulo" do
      proponer
      sugerencia = as_company(company) { AiSuggestion.pending_review.order(:created_at).last }

      post accept_ai_suggestion_path(sugerencia)

      expect(response).to redirect_to(challenge_step_path(challenge, step))
      expect(fields).not_to be_empty
    end

    it "descartarla también" do
      proponer
      sugerencia = as_company(company) { AiSuggestion.pending_review.order(:created_at).last }

      post reject_ai_suggestion_path(sugerencia)

      expect(response).to redirect_to(challenge_step_path(challenge, step))
    end
  end

  describe "guardar" do
    before { sign_in(owner, company: company) }

    it "guarda la lista completa y deriva la clave del nombre" do
      put api_path, params: {
        fields: [{ id: nil, label: "Título", field_type: "text", required: true, is_title: true },
                 { id: nil, label: "¿Cómo funcionaría?", field_type: "textarea", required: false }]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["fields"].map { _1["key"] }).to eq(%w[titulo como_funcionaria])
      expect(json["fields"].map { _1["fieldType"] }).to eq(%w[text textarea])
    end

    it "el orden que llega es el orden que queda" do
      as_company(company) { seed_form!(step) }
      existing = fields

      put api_path, params: {
        fields: existing.reverse.map { |f| { id: f.id, label: f.label, field_type: f.field_type } }
      }, as: :json

      expect(json["fields"].map { _1["key"] }).to eq(%w[solucion problema titulo])
    end

    # `PublishVersion` saca el título con `detect`: si hay dos marcados, el
    # segundo es decoración muda. El server deja uno solo.
    it "el título de la idea es UNO, aunque lleguen dos marcados" do
      put api_path, params: {
        fields: [{ id: nil, label: "Nombre", field_type: "text", is_title: true },
                 { id: nil, label: "Resumen", field_type: "text", is_title: true }]
      }, as: :json

      expect(json["fields"].map { _1["isTitle"] }).to eq([true, false])
    end

    it "y si no llega ninguno, el primero manda: la idea siempre tiene título" do
      put api_path, params: {
        fields: [{ id: nil, label: "Nombre", field_type: "text" },
                 { id: nil, label: "Resumen", field_type: "text" }]
      }, as: :json

      expect(json["fields"].map { _1["isTitle"] }).to eq([true, false])
    end

    it "rechaza el campo sin nombre en vez de guardarlo a medias" do
      put api_path, params: { fields: [{ id: nil, label: "", field_type: "text" }] }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"].join).to include("campo sin nombre")
      expect(fields).to be_empty
    end
  end

  describe "con ideas ya postuladas" do
    before do
      sign_in(owner, company: company)
      as_company(company) do
        seed_form!(step)
        author = Flow::Tenant.bypass! { create(:user) }
        idea = create(:idea, challenge: challenge, author: author)
        Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Sensores" }).call
        idea.update!(submitted_at: Time.current)
      end
    end

    it "avisa en la pantalla que lo estructural quedó cerrado" do
      get challenge_step_path(challenge, step)
      expect(response.body).to include("Ya hay ideas postuladas")
    end

    it "renombrar la etiqueta sigue abierto: no toca las respuestas" do
      existing = fields
      put api_path, params: {
        fields: existing.map { |f| { id: f.id, label: "#{f.label} (v2)", field_type: f.field_type } }
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["fields"].first["label"]).to end_with("(v2)")
    end

    # Las respuestas viven en el payload de cada versión, indexadas por `key`.
    # Cambiar la clave o el tipo, o borrar el campo, las deja huérfanas.
    it "cambiar la clave NO: dejaría huérfano lo ya respondido" do
      existing = fields
      put api_path, params: {
        fields: existing.map { |f| { id: f.id, label: f.label, key: "#{f.key}_nuevo",
                                     field_type: f.field_type } }
      }, as: :json

      expect(fields.map(&:key)).to eq(%w[titulo problema solucion])
    end

    it "quitar un campo tampoco, y lo dice" do
      existing = fields
      put api_path, params: {
        fields: existing.take(1).map { |f| { id: f.id, label: f.label, field_type: f.field_type } }
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"].join).to include("No se pueden quitar campos")
      expect(fields.size).to eq(3)
    end

    it "muestra cuántas ideas respondieron cada campo: ahí se ve el costo" do
      get api_path
      expect(json["fields"].find { _1["key"] == "titulo" }["answered"]).to eq(1)
      expect(json["locked"]).to be(true)
    end
  end

  describe "aislamiento entre empresas" do
    it "el formulario de un desafío ajeno da 404" do
      other = without_tenant { create(:company, slug: "otra") }
      ajeno = as_company(other) do
        c = create(:challenge)
        c.steps.create!(kind: "ideation", position: 1)
        c
      end

      sign_in(owner, company: company)
      get challenge_form_path(ajeno)

      expect(response).to have_http_status(:not_found)
    end
  end
end
