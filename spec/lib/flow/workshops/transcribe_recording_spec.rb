# frozen_string_literal: true

require "rails_helper"

# Transcribir llama a un servicio externo, así que va a un job: parar una
# grabación no puede depender de que Deepgram responda.
RSpec.describe Flow::Workshops::TranscribeRecording do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }
  let!(:ana) { without_tenant { u = create(:user); create(:membership, :participant, company: company, user: u); u } }

  def grabacion(status: "pending", con_audio: true)
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      create(:workshop_group_member, workshop_group: group, user: ana)
      rec = create(:workshop_recording, workshop_group: group, workshop_challenge: link,
                                        recorded_by: ana, status: status)
      if con_audio
        rec.file.attach(io: StringIO.new("bytes"), filename: "mesa.webm",
                        content_type: "audio/webm")
      end
      rec
    end
  end

  before { Flow::AI.reset_provider! }
  after  { Flow::AI.reset_provider! }

  it "escribe las utterances, la duración y la auditoría" do
    rec = grabacion
    as_company(company) do
      Flow::Workshops::TranscribeRecording.call(rec)
      rec.reload

      expect(rec.status).to eq("ready")
      expect(rec.utterances.size).to eq(2)
      expect(rec.utterances.first["transcript"]).to be_present
      expect(rec.provider).to eq("fixture")
      expect(rec.model).to eq("fixture-v1")
    end
  end

  it "es idempotente: sobre una `ready` no vuelve a llamar al proveedor" do
    # No es prolijidad: a diferencia de los embeddings, CADA transcripción se
    # cobra por minuto. Un reintento reintenta una llamada que falló, no
    # re-transcribe una que salió bien.
    rec = grabacion(status: "ready")
    as_company(company) do
      # El objeto REAL con `transcribe` espiado, y no un `instance_double`:
      # devuelve un `Provider::Transcription` y un doble verificador obliga a
      # construirlo a mano para nada.
      proveedor = Flow::AI::Providers::Fixture.new
      allow(proveedor).to receive(:transcribe).and_call_original
      Flow::AI.speech_provider = proveedor

      expect(Flow::Workshops::TranscribeRecording.call(rec)).to be(false)
      expect(proveedor).not_to have_received(:transcribe)
    end
  end

  it "una grabación sin audio queda `failed` con su motivo, y no revienta" do
    rec = grabacion(con_audio: false)
    as_company(company) do
      Flow::Workshops::TranscribeRecording.call(rec)

      expect(rec.reload.status).to eq("failed")
      expect(rec.error).to include("sin audio")
    end
  end

  it "una transcripción vacía queda `ready` y NO `failed`" do
    # Medido: silencio o ruido devuelve 200 con texto vacío. Marcarlo `failed`
    # sería mentir —la llamada salió bien—, y dejarlo `ready` con una tarjeta en
    # blanco sería el control fantasma. La pantalla lo dice.
    rec = grabacion
    as_company(company) do
      # El objeto real, con una transcripción vacía.
      proveedor = Flow::AI::Providers::Fixture.new
      allow(proveedor).to receive(:transcribe).and_return(
        Flow::AI::Provider::Transcription.new(
          utterances: [], duration: nil, request_id: nil, model: "fixture-v1"
        )
      )
      Flow::AI.speech_provider = proveedor

      Flow::Workshops::TranscribeRecording.call(rec)

      expect(rec.reload.status).to eq("ready")
      expect(rec.utterances).to eq([])
      expect(rec.error).to be_nil
    end
  end

  it "si el proveedor falla, la grabación queda `failed` y la excepción se propaga" do
    # Se propaga para que `retry_on` del job la vea: el reintento es del job y no
    # del servicio. El estado se escribe ANTES de propagar, así que la pantalla
    # dice algo aunque los tres reintentos se agoten.
    rec = grabacion
    as_company(company) do
      proveedor = Flow::AI::Providers::Fixture.new
      allow(proveedor).to receive(:transcribe)
        .and_raise(Flow::Errors::TranscriptionFailed, "deepgram respondió 500")
      Flow::AI.speech_provider = proveedor

      expect { Flow::Workshops::TranscribeRecording.call(rec) }
        .to raise_error(Flow::Errors::TranscriptionFailed)

      expect(rec.reload.status).to eq("failed")
      expect(rec.error).to include("500")
    end
  end

  it "dos grabaciones de la misma mesa no se pisan" do
    una = grabacion
    otra = grabacion
    as_company(company) do
      Flow::Workshops::TranscribeRecording.call(una)
      Flow::Workshops::TranscribeRecording.call(otra)

      expect(una.reload.utterances).to be_present
      expect(otra.reload.utterances).to be_present
      expect(una.id).not_to eq(otra.id)
    end
  end

  describe "el job" do
    it "no revienta si la empresa ya no existe" do
      expect { Flow::Workshops::TranscribeRecordingJob.perform_now(SecureRandom.uuid, SecureRandom.uuid) }
        .not_to raise_error
    end

    it "no revienta si la grabación ya no existe" do
      expect { Flow::Workshops::TranscribeRecordingJob.perform_now(company.id, SecureRandom.uuid) }
        .not_to raise_error
    end
  end
end
