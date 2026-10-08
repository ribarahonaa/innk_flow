# frozen_string_literal: true

require "rails_helper"

# La subida del audio de la mesa. Lo dispara un `fetch` al parar de grabar, así
# que contesta códigos y JSON, nunca un redirect.
RSpec.describe "sala del taller: la grabación de la mesa", type: :request do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def member(email, rol = :participant)
    without_tenant do
      u = create(:user, email: email)
      create(:membership, rol, company: company, user: u)
      u
    end
  end

  let!(:ana) { member("ana@test.dev") }
  let!(:beto) { member("beto@test.dev") }

  let!(:idear) do
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      [ ana, beto ].each { |u| create(:workshop_group_member, workshop_group: group, user: u) }
      { workshop: workshop, link: link, group: group, challenge: challenge }
    end
  end

  def audio
    Rack::Test::UploadedFile.new(
      StringIO.new("bytes-de-audio-que-no-se-transcriben-en-el-spec"),
      "audio/webm", original_filename: "mesa.webm"
    )
  end

  def post_recording(setup, params = { file: audio })
    post workshop_sala_recordings_path(setup[:workshop], setup[:link]), params: params
  end

  before { allow(Flow::Workshops::TranscribeRecordingJob).to receive(:perform_later) }

  describe "las guardas, en el mismo orden que los otros POST de la sala" do
    it "sin sesión manda al login" do
      post_recording(idear)

      expect(response).to redirect_to(login_path)
    end

    it "quien administra y no está sentado en ninguna mesa: 403" do
      # `work?` da true por `administers_any?` SIN mesa: es lo que cierra el
      # `group_of`. Un `participant` sin mesa no llega: el scope le da 404.
      admin = member("admin@test.dev", :admin)
      sign_in(admin, company: company)

      post_recording(idear)

      expect(response).to have_http_status(:forbidden)
    end

    it "desde la mesa de llegada, 403" do
      as_company(company) do
        llegada = create(:workshop_group, workshop: idear[:workshop], arrival: true)
        idear[:group].workshop_group_members.destroy_all
        create(:workshop_group_member, workshop_group: llegada, user: ana)
      end
      sign_in(ana, company: company)

      post_recording(idear)

      expect(response).to have_http_status(:forbidden)
    end

    it "con el vínculo cerrado, 409" do
      as_company(company) { idear[:link].update!(status: "closed") }
      sign_in(ana, company: company)

      post_recording(idear)

      expect(response).to have_http_status(:conflict)
    end
  end

  describe "el POST sin archivo" do
    it "contesta 400 y no crea nada" do
      # Sin esto, `attach(nil)` revienta con un 500 y la mesa ve una pantalla de
      # error en vez de un motivo.
      sign_in(ana, company: company)

      expect { post_recording(idear, {}) }.not_to change { as_company(company) { WorkshopRecording.count } }
      expect(response).to have_http_status(:bad_request)
    end

    it "con un archivo que no es audio, 415" do
      sign_in(ana, company: company)
      texto = Rack::Test::UploadedFile.new(
        StringIO.new("no soy audio"), "text/plain", original_filename: "x.txt"
      )

      post_recording(idear, { file: texto })

      expect(response).to have_http_status(:unsupported_media_type)
    end
  end

  describe "el camino feliz" do
    it "crea la grabación pendiente, adjunta el audio y encola el job" do
      sign_in(ana, company: company)

      post_recording(idear)

      expect(response).to have_http_status(:created)
      grabacion = as_company(company) { WorkshopRecording.last }
      expect(grabacion.status).to eq("pending")
      expect(grabacion.recorded_by).to eq(ana)
      as_company(company) do
        expect(grabacion.workshop_group).to eq(idear[:group])
        expect(grabacion.file).to be_attached
      end
      expect(Flow::Workshops::TranscribeRecordingJob)
        .to have_received(:perform_later).with(company.id, grabacion.id)
    end

    it "acepta el tipo con parámetro, que es lo que manda MediaRecorder" do
      # Chromium manda `audio/webm;codecs=opus`: se compara el tipo base.
      sign_in(ana, company: company)
      opus = Rack::Test::UploadedFile.new(
        StringIO.new("bytes"), "audio/webm;codecs=opus", original_filename: "mesa.webm"
      )

      post_recording(idear, { file: opus })

      expect(response).to have_http_status(:created)
    end

    it "devuelve el id en el cuerpo, que es lo que el JS necesita" do
      sign_in(ana, company: company)

      post_recording(idear)

      expect(response.parsed_body["id"]).to eq(as_company(company) { WorkshopRecording.last.id })
    end

    it "dos personas de la mesa pueden grabar a la vez: son dos filas" do
      # No hay índice único, a diferencia del borrador. Lo que no puede pasar es
      # que una pise a la otra.
      sign_in(ana, company: company)
      post_recording(idear)
      sign_in(beto, company: company)
      post_recording(idear)

      expect(as_company(company) { WorkshopRecording.count }).to eq(2)
    end
  end

  describe "servir el audio" do
    it "lo devuelve a quien está en la mesa" do
      sign_in(ana, company: company)
      post_recording(idear)
      grabacion = as_company(company) { WorkshopRecording.last }

      get workshop_sala_recording_path(idear[:workshop], idear[:link], grabacion)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("audio/webm")
    end

    it "una grabación de otra empresa da 404, no 403" do
      # Un 403 sería un oráculo de existencia. La fila se busca DENTRO de la
      # sala, que ya se buscó por `policy_scope`.
      otra = without_tenant { create(:company, slug: "otra") }
      ajena = as_company(otra) do
        challenge = create(:challenge)
        step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
        workshop = create(:workshop, status: "open")
        link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                           challenge_step: step)
        group = create(:workshop_group, workshop: workshop)
        create(:workshop_recording, :ready, workshop_group: group, workshop_challenge: link,
                                            recorded_by: create(:user))
      end
      # Con audio adjunto: sin él, el 404 lo daría `send_attached_file` aunque la
      # búsqueda encontrara la fila ajena, y el ejemplo no probaría el scope.
      as_company(otra) { ajena.file.attach(io: StringIO.new("x"), filename: "a.webm", content_type: "audio/webm") }
      sign_in(ana, company: company)

      get workshop_sala_recording_path(idear[:workshop], idear[:link], ajena)

      expect(response).to have_http_status(:not_found)
    end

    it "una grabación sin audio adjunto da 404 y no 500" do
      # El caso llega de verdad: la fila se crea antes de adjuntar.
      grabacion = as_company(company) do
        create(:workshop_recording, workshop_group: idear[:group],
                                    workshop_challenge: idear[:link], recorded_by: ana)
      end
      sign_in(ana, company: company)

      get workshop_sala_recording_path(idear[:workshop], idear[:link], grabacion)

      expect(response).to have_http_status(:not_found)
    end
  end
end
