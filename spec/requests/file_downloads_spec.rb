# frozen_string_literal: true

require "rails_helper"

# Los dos archivos que la app entrega: el adjunto de una idea y el reporte
# generado de un módulo.
#
# Los dos se servían con `rails_blob_path`, o sea por el controller de Active
# Storage, que verifica la firma del blob y NADA más: sin sesión, sin membresía,
# sin Pundit, sin tenant, y con una firma que no vence. Quien tuviera la URL
# bajaba el archivo para siempre, sin sesión y desde cualquier empresa — las
# cuatro capas de tenencia salteadas por un camino de lectura. Ahora los sirve
# la app, y lo que cuelga de una idea hereda la visibilidad de la idea.
RSpec.describe "bajar archivos", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, role = nil)
    without_tenant do
      u = create(:user, email: email)
      role ? create(:membership, role.to_sym, company: company, user: u) : create(:membership, company: company, user: u)
      u
    end
  end

  let!(:owner) { member("owner@test.dev", :owner) }
  let!(:autora) { member("autora@test.dev") }
  let!(:ajena) { member("ajena@test.dev") }

  let!(:challenge) do
    as_company(company) do
      c = create(:challenge, name: "Merma")
      step = c.steps.create!(kind: "ideation", position: 1, name: "Postulación")
      seed_form!(step)
      step.form_fields.create!(key: "costeo", label: "Costeo", field_type: "file", position: 3)
      c
    end
  end

  def upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/costeo.txt"), "text/plain")

  # Se sube por el camino real —un PATCH que publica versión— y no atacando el
  # blob a mano, así el adjunto queda como lo deja la app.
  def idea_con_adjunto(author)
    idea = as_company(company) do
      i = create(:idea, challenge: challenge, author: author)
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores" }, author: author).call
      i
    end
    sign_in(author, company: company)
    patch challenge_idea_path(challenge, idea),
          params: { payload: { titulo: "Sensores" }, files: { costeo: upload } }
    as_company(company) { Idea.find(idea.id) }
  end

  def adjunto_de(idea) = as_company(company) { idea.current_version.attachments.first }

  describe "el adjunto de una idea" do
    let!(:propia) { idea_con_adjunto(autora) }

    it "lo baja quien la escribió" do
      sign_in(autora, company: company)
      get challenge_idea_attachment_path(challenge, propia, adjunto_de(propia))

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("attachment", "costeo.txt")
      expect(response.body).to eq("costeo del piloto: 4.2M CLP\n")
    end

    it "lo baja quien administra" do
      sign_in(owner, company: company)
      get challenge_idea_attachment_path(challenge, propia, adjunto_de(propia))

      expect(response).to have_http_status(:ok)
    end

    # Quien participa ve solo las ideas en las que participa, y el adjunto
    # hereda esa regla: lo que no se ve da 404, no 403.
    it "quien no participa de esa idea recibe 404" do
      sign_in(ajena, company: company)
      get challenge_idea_attachment_path(challenge, propia, adjunto_de(propia))

      expect(response).to have_http_status(:not_found)
    end

    it "sin sesión no entrega el archivo" do
      ruta = challenge_idea_attachment_path(challenge, propia, adjunto_de(propia))
      # `propia` se sube firmando como la autora, así que sin esto el ejemplo
      # correría CON sesión y pasaría por el motivo equivocado.
      reset!

      get ruta

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include("4.2M CLP")
    end

    # El ataque real no es un id inexistente —eso ya daba 404— sino el id de un
    # adjunto AJENO sobre una idea que sí ves: si el adjunto se busca por id en
    # toda la empresa, la idea visible funciona de llave para el archivo de otra.
    it "el adjunto de otra idea, sobre una idea visible, da 404" do
      de_otra = adjunto_de(idea_con_adjunto(ajena))

      sign_in(autora, company: company)
      get challenge_idea_attachment_path(challenge, propia, de_otra)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("4.2M CLP")
    end

    it "y un adjunto de otra empresa tampoco" do
      otra = without_tenant { create(:company, slug: "otra") }
      ajeno_id = as_company(otra) do
        c = create(:challenge, name: "Otra")
        c.steps.create!(kind: "ideation", position: 1, name: "Postulación")
        i = create(:idea, challenge: c)
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "X" }).call
        IdeaAttachment.create!(idea_version: i.reload.current_version, field_key: "costeo").id
      end

      sign_in(autora, company: company)
      get challenge_idea_attachment_path(challenge, propia, ajeno_id)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "el reporte de un módulo" do
    # Activo a propósito: la cara de ejecución es la que trae las descargas.
    let!(:step) do
      as_company(company) do
        challenge.steps.create!(kind: "reporting", position: 2, name: "Tablero", status: "active")
      end
    end

    let!(:report) do
      as_company(company) do
        r = Report.create!(challenge_step: step, kind: "funnel", format: "xlsx",
                           status: "ready", scope: {})
        r.file.attach(io: StringIO.new("embudo"), filename: "embudo.xlsx")
        r
      end
    end

    it "lo baja quien administra el desafío" do
      sign_in(owner, company: company)
      get download_challenge_step_report_path(challenge, step, report)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("attachment", "embudo.xlsx")
      expect(response.body).to eq("embudo")
    end

    # Quien participa ve lo agregado de reportería, no el archivo crudo. Acá 403
    # y no 404: el desafío lo ve, así que negarle esto no confirma nada.
    it "quien participa no lo baja" do
      sign_in(autora, company: company)
      get download_challenge_step_report_path(challenge, step, report)

      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("embudo")
    end

    it "sin sesión tampoco" do
      get download_challenge_step_report_path(challenge, step, report)

      expect(response).not_to have_http_status(:ok)
    end

    # Ningún otro spec renderiza esta fila: el único reporte `ready` de la suite
    # es un dashboard SIN archivo, así que el link del partial vivía sin que
    # nada lo ejecutara —un helper mal escrito daba verde acá y 500 en la
    # pantalla—. Esto ata la vista a la ruta.
    it "la pantalla del módulo linkea el archivo por la app" do
      sign_in(owner, company: company)
      get challenge_step_path(challenge, step)

      expect(response.body).to include(download_challenge_step_report_path(challenge, step, report))
      expect(response.body).not_to include("/rails/active_storage")
    end
  end

  # La puerta vieja se cierra, no se deja de usar: sin esto, toda URL ya emitida
  # —un historial, un link pegado— sigue sirviendo el archivo para siempre, y la
  # ruta queda abierta para cualquier cosa que se suba después.
  it "las rutas de Active Storage ya no existen" do
    rutas = Rails.application.routes.routes.map { |r| r.path.spec.to_s }
                 .grep(%r{^/rails/active_storage})

    expect(rutas).to be_empty
  end
end
