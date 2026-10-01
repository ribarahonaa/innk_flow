# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flow::Workshops::Open do
  let!(:company) { without_tenant { create(:company, slug: "acme") } }

  def challenge_with(kind)
    challenge = create(:challenge)
    step = create(:challenge_step, challenge: challenge, kind: kind, status: "active")
    [challenge, step]
  end

  it "resuelve el módulo activo de cada desafío al abrir" do
    as_company(company) do
      challenge, step = challenge_with("ideation")
      workshop = create(:workshop)
      link = create(:workshop_challenge, workshop: workshop, challenge: challenge)

      result = described_class.new(workshop).call

      expect(result.ok).to be(true)
      expect(workshop.reload).to be_open
      expect(link.reload.challenge_step_id).to eq(step.id)
    end
  end

  # Review Focus 2: entre el armado y la apertura, el desafío pudo avanzar.
  it "rechaza el desafío cuyo módulo activo no es idear ni evolución, y abre igual el resto" do
    as_company(company) do
      good_challenge, = challenge_with("evolution")
      bad_challenge, = challenge_with("evaluation")
      workshop = create(:workshop)
      good_link = create(:workshop_challenge, workshop: workshop, challenge: good_challenge)
      bad_link = create(:workshop_challenge, workshop: workshop, challenge: bad_challenge)

      result = described_class.new(workshop).call

      expect(result.ok).to be(true)
      expect(result.rejected.map(&:id)).to eq([bad_link.id])
      expect(bad_link.reload).to be_closed
      expect(bad_link.closed_reason).to include("Evaluación")
      expect(good_link.reload).to be_open
      expect(workshop.reload).to be_open
    end
  end

  it "no abre un taller sin ningún desafío trabajable" do
    as_company(company) do
      bad_challenge, = challenge_with("reporting")
      workshop = create(:workshop)
      create(:workshop_challenge, workshop: workshop, challenge: bad_challenge)

      result = described_class.new(workshop).call

      expect(result.ok).to be(false)
      expect(workshop.reload).to be_draft
    end
  end

  # El rollback tiene que ser total: un intento fallido no puede dejar un
  # vínculo cerrado a medias mientras el taller entero sigue en borrador.
  it "no deja vínculos cerrados cuando el intento de apertura falla entero" do
    as_company(company) do
      bad_challenge, = challenge_with("reporting")
      workshop = create(:workshop)
      link = create(:workshop_challenge, workshop: workshop, challenge: bad_challenge)

      result = described_class.new(workshop).call

      expect(result.ok).to be(false)
      expect(link.reload).to be_open
      expect(link.closed_reason).to be_nil
      expect(link.closed_at).to be_nil
    end
  end

  # Fix round 1: sin ningún desafío trabajable y con más de uno no
  # trabajable, el rollback deshace los dos `update!` a "closed". El
  # `Result` tiene que decir lo mismo que la base: nada se rechazó porque
  # nada se abrió. Devolver el array viejo (con los vínculos en memoria en
  # estado "closed") haría fallar la primera aserción, aunque la base esté
  # bien.
  it "no informa vínculos rechazados cuando el intento de apertura falla entero" do
    as_company(company) do
      first_bad, = challenge_with("evaluation")
      second_bad, = challenge_with("reporting")
      workshop = create(:workshop)
      first_link = create(:workshop_challenge, workshop: workshop, challenge: first_bad)
      second_link = create(:workshop_challenge, workshop: workshop, challenge: second_bad)

      result = described_class.new(workshop).call

      expect(result.ok).to be(false)
      expect(result.rejected).to eq([])
      expect(first_link.reload).to be_open
      expect(first_link.closed_at).to be_nil
      expect(second_link.reload).to be_open
      expect(second_link.closed_at).to be_nil
    end
  end

  # Un taller es de UNA fase. Se verifica acá y no en `WorkshopChallenge`
  # porque en borrador `challenge_step` es nil: la fase todavía no existe.
  describe "fase mixta" do
    it "no abre, y nada cambia" do
      as_company(company) do
        en_idear, = challenge_with("ideation")
        en_evolucion, = challenge_with("evolution")
        workshop = create(:workshop)
        create(:workshop_challenge, workshop: workshop, challenge: en_idear)
        create(:workshop_challenge, workshop: workshop, challenge: en_evolucion)

        result = described_class.new(workshop).call

        expect(result).not_to be_ok
        expect(workshop.reload).to be_draft
        expect(workshop.workshop_challenges.reload.map(&:status).uniq).to eq(["open"])
        expect(workshop.workshop_challenges.map(&:challenge_step_id).compact).to be_empty
      end
    end

    it "y el error nombra qué desafío está en cuál fase" do
      as_company(company) do
        en_idear, = challenge_with("ideation")
        en_evolucion, = challenge_with("evolution")
        workshop = create(:workshop)
        create(:workshop_challenge, workshop: workshop, challenge: en_idear)
        create(:workshop_challenge, workshop: workshop, challenge: en_evolucion)

        result = described_class.new(workshop).call

        expect(result.errors.join).to include(en_idear.name, en_evolucion.name, "Idear", "Evolución")
      end
    end
  end
end
