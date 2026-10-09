# frozen_string_literal: true

require "rails_helper"

# El testigo de la CADENA de «entrar a una mesa»: render -> URL de acción en el
# HTML servido -> escritura. `escribir_en_una_mesa_ajena_spec.rb` manda `mesa:`
# a mano en los params, o sea que prueba el servidor y no la cadena: con las
# vistas armando sus URLs SIN el parámetro, sus 18 ejemplos seguían verdes y
# toda escritura de quien administra y no está sentado rebotaba en el navegador.
#
# Acá la URL de cada escritura se SACA del HTML que sirve la sala con `?mesa=`,
# y es contra ESA que se escribe. Si una vista pierde el parámetro, el pedido
# va sin él, cae a `own_group` (nil) y el ejemplo se pone rojo.
# Mismo patrón que `spec/lint/sello_del_borrador_spec.rb` para `base_version_id`,
# pero con runtime: acá el eslabón del medio (el HTML) sí se puede leer.
RSpec.describe "la mesa viaja en la escritura", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, rol = :participant)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, rol, company: company, user: u)
      u
    end
  end

  let!(:ana) { member("ana@test.dev") }
  let!(:admin) { member("admin@test.dev", :admin) }

  let!(:idear) do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      field = create(:form_field, challenge_step: step, label: "Resumen", field_type: "text")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: step)
      mesa = create(:workshop_group, workshop: workshop, name: "Mesa del fondo")
      create(:workshop_group_member, workshop_group: mesa, user: ana)
      { workshop: workshop, link: link, mesa: mesa, field: field }
    end
  end

  let!(:evolucion) do
    as_company(company) do
      challenge = create(:challenge)
      ideation = create(:challenge_step, challenge: challenge, kind: "ideation", status: "completed")
      field = create(:form_field, challenge_step: ideation, label: "Resumen", field_type: "text")
      round = create(:challenge_step, challenge: challenge, kind: "evolution", status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge, challenge_step: round)
      mesa = create(:workshop_group, workshop: workshop, name: "Mesa del fondo")
      create(:workshop_group_member, workshop_group: mesa, user: ana)
      idea = create(:idea, challenge: challenge, author: ana, status: "active")
      Flow::Ideas::PublishVersion.new(idea, payload: { field.key => "lo publicado" }, author: ana).call
      { workshop: workshop, link: link, mesa: mesa, field: field, idea: idea }
    end
  end

  # Quien administra y NO está sentado entra a la mesa ajena por el «Entrar».
  def enter(setup, **extra)
    sign_in(admin, company: company)
    get workshop_sala_path(setup[:workshop], setup[:link], mesa: setup[:mesa].id, **extra)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  def draft_url_of(doc)
    CGI.unescapeHTML(doc.at_css("form[data-draft-url]")["data-draft-url"])
  end

  def audio
    Rack::Test::UploadedFile.new(StringIO.new("bytes-de-audio"), "audio/webm",
                                 original_filename: "mesa.webm")
  end

  before { allow(Flow::Workshops::TranscribeRecordingJob).to receive(:perform_later) }

  describe "idear" do
    it "la idea nueva se escribe contra la URL del formulario servido" do
      doc = enter(idear)
      action = doc.css("form").map { |f| f["action"] }.find { |a| a.include?("/ideas") }

      expect do
        post action, params: { payload: { idear[:field].key => "Una idea" } }
      end.to(change { as_company(company) { Idea.count } }.by(1))
    end

    it "el borrador se escribe contra la draft_url servida" do
      doc = enter(idear)

      patch draft_url_of(doc), params: { payload: { idear[:field].key => "texto" } }

      expect(response).to have_http_status(:no_content)
      expect(as_company(company) { WorkshopDraft.last.workshop_group }).to eq(idear[:mesa])
    end

    it "la grabación se sube contra la recording_url servida" do
      doc = enter(idear)
      url = CGI.unescapeHTML(doc.at_css("[data-recording-url]")["data-recording-url"])

      expect { post url, params: { file: audio } }
        .to(change { as_company(company) { WorkshopRecording.count } }.by(1))
    end
  end

  describe "evolución" do
    it "la propuesta se escribe contra la URL del formulario servido" do
      doc = enter(evolucion, idea: evolucion[:idea].id)
      action = doc.css("form").map { |f| f["action"] }.find { |a| a.include?("/proposals") }

      expect do
        post action, params: { idea_id: evolucion[:idea].id,
                               payload: { evolucion[:field].key => "Mejor así" } }
      end.to(change { as_company(company) { WorkshopProposal.count } }.by(1))
    end

    it "el borrador se escribe contra la draft_url servida" do
      doc = enter(evolucion, idea: evolucion[:idea].id)

      patch draft_url_of(doc), params: { idea_id: evolucion[:idea].id,
                                         payload: { evolucion[:field].key => "texto" } }

      expect(response).to have_http_status(:no_content)
      expect(as_company(company) { WorkshopDraft.last.workshop_group }).to eq(evolucion[:mesa])
    end

    it "la grabación se sube contra la recording_url servida" do
      doc = enter(evolucion, idea: evolucion[:idea].id)
      url = CGI.unescapeHTML(doc.at_css("[data-recording-url]")["data-recording-url"])

      expect { post url, params: { file: audio, idea_id: evolucion[:idea].id } }
        .to(change { as_company(company) { WorkshopRecording.count } }.by(1))
    end
  end
end
