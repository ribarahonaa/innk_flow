# frozen_string_literal: true

require "rails_helper"

# La grabación de una mesa. Clavijada como `WorkshopDraft` pero SIN índice
# único: una mesa graba varias veces en una sesión.
RSpec.describe WorkshopRecording do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  # Toda lectura del dominio va dentro de `as_company`, incluido un `.new`: toca
  # el `default_scope` de `TenantScoped`.
  def armar
    as_company(company) do
      challenge = create(:challenge)
      step = create(:challenge_step, challenge: challenge, kind: "ideation", status: "active")
      workshop = create(:workshop, status: "open")
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge,
                                         challenge_step: step)
      group = create(:workshop_group, workshop: workshop)
      { workshop: workshop, link: link, group: group, challenge: challenge }
    end
  end

  it "una mesa puede tener VARIAS grabaciones de la misma sala" do
    s = armar
    as_company(company) do
      create(:workshop_recording, workshop_group: s[:group], workshop_challenge: s[:link])

      expect {
        create(:workshop_recording, workshop_group: s[:group], workshop_challenge: s[:link])
      }.to change { s[:group].workshop_recordings.count }.by(1)
    end
  end

  it "rechaza una mesa y una sala de talleres distintos" do
    s = armar
    as_company(company) do
      otra_mesa = create(:workshop_group, workshop: create(:workshop, status: "open"))
      grabacion = WorkshopRecording.new(workshop_group: otra_mesa,
                                        workshop_challenge: s[:link],
                                        recorded_by: create(:user), status: "pending")

      expect(grabacion).not_to be_valid
      expect(grabacion.errors[:workshop_group]).to be_present
    end
  end

  it "rechaza una idea de otro desafío que el de la sala" do
    s = armar
    as_company(company) do
      ajena = create(:idea, challenge: create(:challenge))
      grabacion = build(:workshop_recording, workshop_group: s[:group],
                                             workshop_challenge: s[:link], idea: ajena)

      expect(grabacion).not_to be_valid
      expect(grabacion.errors[:idea]).to be_present
    end
  end

  it "rechaza un status que no está en la lista" do
    s = armar
    as_company(company) do
      grabacion = build(:workshop_recording, workshop_group: s[:group],
                                             workshop_challenge: s[:link], status: "wat")

      expect(grabacion).not_to be_valid
    end
  end

  describe "#transcript_text" do
    it "concatena las utterances con su hablante" do
      s = armar
      as_company(company) do
        grabacion = build(:workshop_recording, :ready, workshop_group: s[:group],
                                                       workshop_challenge: s[:link])

        expect(grabacion.transcript_text).to eq(
          "Hablante 1: Primera.\nHablante 2: Segunda."
        )
      end
    end

    it "sin utterances devuelve cadena vacía y no revienta" do
      s = armar
      as_company(company) do
        grabacion = build(:workshop_recording, workshop_group: s[:group],
                                               workshop_challenge: s[:link])

        expect(grabacion.transcript_text).to eq("")
      end
    end
  end

  describe "#collapsed_diarization?" do
    it "es true con un solo hablante y dos sentados en la mesa" do
      s = armar
      as_company(company) do
        2.times { create(:workshop_group_member, workshop_group: s[:group], user: create(:user)) }
        grabacion = create(:workshop_recording, :colapsada, workshop_group: s[:group],
                                                            workshop_challenge: s[:link])

        expect(grabacion.collapsed_diarization?).to be(true)
      end
    end

    it "es false con dos hablantes, aunque la confianza sea baja" do
      # A propósito: NO hay umbral sobre `speaker_confidence`. Se midió
      # 0,196–0,687 sobre entrada degenerada y no hay línea base de voces
      # reales, así que cualquier corte sería un número inventado — y un umbral
      # inventado es la guarda que da permiso. La condición es estructural.
      s = armar
      as_company(company) do
        2.times { create(:workshop_group_member, workshop_group: s[:group], user: create(:user)) }
        grabacion = create(:workshop_recording, :ready, workshop_group: s[:group],
                                                        workshop_challenge: s[:link])

        expect(grabacion.collapsed_diarization?).to be(false)
      end
    end

    it "es false con una sola persona sentada: ahí un hablante es correcto" do
      s = armar
      as_company(company) do
        create(:workshop_group_member, workshop_group: s[:group], user: create(:user))
        grabacion = create(:workshop_recording, :colapsada, workshop_group: s[:group],
                                                            workshop_challenge: s[:link])

        expect(grabacion.collapsed_diarization?).to be(false)
      end
    end

    it "es false si la segunda persona de la mesa no vino: su voz no puede estar" do
      s = armar
      as_company(company) do
        create(:workshop_group_member, workshop_group: s[:group], user: create(:user))
        create(:workshop_group_member, workshop_group: s[:group], user: create(:user),
                                       attended: false)
        grabacion = create(:workshop_recording, :colapsada, workshop_group: s[:group],
                                                            workshop_challenge: s[:link])

        expect(grabacion.collapsed_diarization?).to be(false)
      end
    end

    it "es false sin utterances: la condición es una igualdad y no un `<=`" do
      # Caza la mutación `speakers.size == 1` -> `<= 1`: con cero hablantes y dos
      # sentados, empezaría a avisar de una diarización colapsada que no existe.
      s = armar
      as_company(company) do
        2.times { create(:workshop_group_member, workshop_group: s[:group], user: create(:user)) }
        grabacion = create(:workshop_recording, workshop_group: s[:group],
                                                workshop_challenge: s[:link], status: "ready")

        expect(grabacion.collapsed_diarization?).to be(false)
      end
    end
  end
end
