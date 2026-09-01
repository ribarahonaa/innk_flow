# frozen_string_literal: true

require "rails_helper"

# La regla dura del producto vive acá.
#
#   Borrador: agregar, reordenar y borrar libremente.
#   En curso: solo se puede insertar DESPUÉS del último módulo ya ejecutado
#             o en curso. Nunca antes, nunca intercalado.
RSpec.describe Flow::Pipeline do
  let(:company) { without_tenant { create(:company) } }

  around { |example| as_company(company) { example.run } }

  # Arma un pipeline con los kinds y estados dados.
  #   build_pipeline(%w[ideation:completed evaluation:active selection:pending])
  def build_pipeline(spec, challenge_status: "running")
    challenge = create(:challenge, status: "draft")
    spec.each_with_index do |token, index|
      kind, status = token.split(":")
      challenge.steps.create!(kind: kind, position: index + 1, status: status || "pending")
    end
    challenge.update!(status: challenge_status)
    challenge.steps.reset
    challenge
  end

  describe "#insertion_floor" do
    it "es nil en borrador: no hay piso, todo es reordenable" do
      challenge = build_pipeline(%w[ideation evaluation selection], challenge_status: "draft")
      expect(described_class.new(challenge).insertion_floor).to be_nil
    end

    it "en curso, es la posición del último módulo tocado" do
      challenge = build_pipeline(%w[ideation:completed evaluation:active selection:pending])
      expect(described_class.new(challenge).insertion_floor).to eq(2)
    end

    it "un módulo SALTEADO también sube el piso" do
      # Saltear no reabre la puerta a insertar antes: fue tocado igual.
      challenge = build_pipeline(%w[ideation:completed evolution:skipped evaluation:pending])
      expect(described_class.new(challenge).insertion_floor).to eq(2)
    end

    it "es nil si nada se tocó todavía, aunque el desafío esté en curso" do
      challenge = build_pipeline(%w[ideation evaluation])
      expect(described_class.new(challenge).insertion_floor).to be_nil
    end
  end

  describe "#can_place_at?" do
    let(:challenge) { build_pipeline(%w[ideation:completed evaluation:active selection:pending]) }
    let(:pipeline) { described_class.new(challenge) }

    it "rechaza posiciones ANTES del piso" do
      expect(pipeline.can_place_at?(0.5)).to be(false)
      expect(pipeline.can_place_at?(1.5)).to be(false)
    end

    it "rechaza la posición del piso mismo" do
      expect(pipeline.can_place_at?(2)).to be(false)
    end

    it "acepta inmediatamente después del módulo en curso" do
      # "a partir del último ejecutado" incluye el hueco entre el activo y el
      # siguiente pendiente.
      expect(pipeline.can_place_at?(2.5)).to be(true)
      expect(pipeline.can_place_at?(4)).to be(true)
    end
  end

  describe "insertar con el flujo ya arrancado" do
    let(:challenge) { build_pipeline(%w[ideation:completed evaluation:active selection:pending]) }
    let(:pipeline) { described_class.new(challenge) }

    it "permite agregar al final" do
      result = pipeline.insert(kind: "reporting", after: :end)
      expect(result).to be_ok
      expect(challenge.steps.ordered.last.kind).to eq("reporting")
    end

    it "permite intercalar entre el módulo en curso y el siguiente pendiente" do
      active = challenge.steps.find_by(status: "active")
      result = pipeline.insert(kind: "evolution", after: active)

      expect(result).to be_ok
      expect(result.step.position.to_d).to be_between(2, 3).exclusive
      expect(challenge.steps.ordered.map(&:kind))
        .to eq(%w[ideation evaluation evolution selection])
    end

    it "RECHAZA insertar antes del primer módulo" do
      result = pipeline.insert(kind: "evolution", after: nil)

      expect(result).not_to be_ok
      expect(result.error_sentence).to match(/antes ni entre módulos ya ejecutados/)
    end

    it "RECHAZA intercalar entre dos módulos ya ejecutados" do
      challenge = build_pipeline(%w[ideation:completed evaluation:completed selection:pending])
      first = challenge.steps.ordered.first
      result = described_class.new(challenge).insert(kind: "evolution", after: first)

      expect(result).not_to be_ok
      expect(result.error_sentence).to match(/antes ni entre módulos ya ejecutados/)
    end

    it "la validación no se puede saltear desde la consola" do
      # ChallengeStep replica la regla: Pipeline es la API cómoda, no la única.
      step = challenge.steps.find_by(kind: "selection")
      step.position = 1.5

      expect(step).not_to be_valid
      expect(step.errors[:position].join).to match(/antes ni entre módulos ya ejecutados/)
    end
  end

  describe "insertar en borrador" do
    let(:challenge) { build_pipeline(%w[ideation evaluation], challenge_status: "draft") }

    it "permite insertar en cualquier lado, incluido el principio" do
      result = described_class.new(challenge).insert(kind: "reporting", after: nil)

      expect(result).to be_ok
      expect(challenge.steps.ordered.first.kind).to eq("reporting")
    end
  end

  describe "#remove" do
    it "permite quitar un módulo pendiente por encima del piso" do
      challenge = build_pipeline(%w[ideation:completed evaluation:active selection:pending])
      step = challenge.steps.find_by(kind: "selection")

      expect(described_class.new(challenge).remove(step)).to be_ok
    end

    it "RECHAZA quitar un módulo ya ejecutado" do
      challenge = build_pipeline(%w[ideation:completed evaluation:active])
      step = challenge.steps.find_by(kind: "ideation")

      result = described_class.new(challenge).remove(step)
      expect(result).not_to be_ok
      expect(result.error_sentence).to match(/no se puede quitar/)
    end
  end

  describe "#reorder" do
    it "renumera a enteros contiguos en borrador" do
      challenge = build_pipeline(%w[ideation evaluation selection], challenge_status: "draft")
      ids = challenge.steps.ordered.to_a
      reversed = [ids[0], ids[2], ids[1]].map(&:id)

      expect(described_class.new(challenge).reorder(reversed)).to be_ok
      expect(challenge.steps.ordered.map(&:kind)).to eq(%w[ideation selection evaluation])
      expect(challenge.steps.ordered.map { |s| s.position.to_d }).to eq([1, 2, 3])
    end

    it "RECHAZA mover un módulo ya ejecutado" do
      challenge = build_pipeline(%w[ideation:completed evaluation:active selection:pending])
      ids = challenge.steps.ordered.map(&:id)

      result = described_class.new(challenge).reorder([ids[2], ids[0], ids[1]])
      expect(result).not_to be_ok
      expect(result.error_sentence).to match(/ya ejecutados no se pueden reordenar/)
    end

    it "PERMITE reacomodar los pendientes con el flujo en curso" do
      # La regla limita dónde se puede COLOCAR algo, no prohíbe reacomodar lo
      # que todavía no pasó. El prefijo tocado tiene que llegar intacto.
      challenge = build_pipeline(%w[ideation:completed evaluation:active selection:pending reporting:pending])
      ids = challenge.steps.ordered.map(&:id)

      result = described_class.new(challenge).reorder([ids[0], ids[1], ids[3], ids[2]])
      expect(result).to be_ok
      expect(challenge.steps.ordered.map(&:kind)).to eq(%w[ideation evaluation reporting selection])
    end

    it "RECHAZA una lista que no coincide con los módulos del desafío" do
      challenge = build_pipeline(%w[ideation evaluation], challenge_status: "draft")
      result = described_class.new(challenge).reorder([challenge.steps.first.id])

      expect(result).not_to be_ok
      expect(result.error_sentence).to match(/no coincide/)
    end
  end

  describe "«Idear» es único" do
    it "rechaza un segundo módulo de ideación" do
      challenge = build_pipeline(%w[ideation evaluation], challenge_status: "draft")
      result = described_class.new(challenge).insert(kind: "ideation", after: :end)

      expect(result).not_to be_ok
      expect(result.error_sentence).to match(/una sola vez/)
    end

    it "la unicidad también está en la base, no solo en el modelo" do
      challenge = build_pipeline(%w[ideation], challenge_status: "draft")

      expect do
        challenge.steps.new(kind: "ideation", position: 9, slug: "ideation_manual", name: "Idear otra vez")
                 .save!(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#validate" do
    it "exige un módulo de ideación" do
      challenge = build_pipeline(%w[evaluation], challenge_status: "draft")
      expect(described_class.new(challenge).validate.errors.join).to match(/Falta el módulo/)
    end

    it "exige que una selección tenga una evaluación previa resoluble" do
      challenge = build_pipeline(%w[ideation selection], challenge_status: "draft")
      expect(described_class.new(challenge).validate.errors.join).to match(/no tiene ninguna evaluación previa/)
    end

    it "acepta un pipeline coherente" do
      challenge = build_pipeline(%w[ideation evaluation selection reporting], challenge_status: "draft")
      expect(described_class.new(challenge).validate).to be_valid
    end

    it "advierte sobre dos selecciones seguidas sin bloquear" do
      challenge = build_pipeline(%w[ideation evaluation selection selection], challenge_status: "draft")
      report = described_class.new(challenge).validate

      expect(report).to be_valid
      expect(report.warnings.join).to match(/dos selecciones seguidas/)
    end
  end

  describe "#start! y #advance!" do
    it "no arranca un pipeline inválido" do
      challenge = build_pipeline(%w[evaluation], challenge_status: "draft")
      result = described_class.new(challenge).start!

      expect(result).not_to be_ok
      expect(challenge.reload).to be_draft
    end

    it "arranca y activa el primer módulo" do
      challenge = build_pipeline(%w[ideation evaluation], challenge_status: "draft")
      result = described_class.new(challenge).start!

      expect(result).to be_ok
      expect(challenge.reload).to be_running
      expect(challenge.steps.ordered.first.reload).to be_active
    end

    it "NO avanza si el módulo en curso no cumple sus condiciones" do
      # «Idear» exige al menos una idea postulada. El flujo no se cierra por
      # decreto: cada handler decide cuándo está listo.
      challenge = build_pipeline(%w[ideation evaluation], challenge_status: "draft")
      pipeline = described_class.new(challenge)
      pipeline.start!

      result = pipeline.advance!
      expect(result).not_to be_ok
      expect(result.error_sentence).to match(/al menos 1 idea postulada/)
      expect(challenge.steps.ordered.first.reload).to be_active
    end

    it "avanza al siguiente y cierra al terminar" do
      challenge = build_pipeline(%w[ideation reporting], challenge_status: "draft")
      pipeline = described_class.new(challenge)
      pipeline.start!

      idea = create(:idea, challenge: challenge)
      Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Una idea" }).call
      idea.update!(submitted_at: Time.current)

      pipeline.advance!
      expect(challenge.steps.ordered.first.reload).to be_completed
      expect(challenge.steps.ordered.last.reload).to be_active

      pipeline.advance!
      expect(challenge.reload).to be_closed
    end

    it "un módulo de evaluación no se cierra sin evaluaciones" do
      challenge = build_pipeline(%w[ideation evaluation], challenge_status: "draft")
      pipeline = described_class.new(challenge)
      pipeline.start!

      idea = create(:idea, challenge: challenge)
      Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Una idea" }).call
      idea.update!(submitted_at: Time.current)
      pipeline.advance!

      result = pipeline.advance!
      expect(result).not_to be_ok
      expect(result.error_sentence).to match(/Faltan evaluaciones/)
    end
  end

  describe "config vs resolved_config" do
    it "un step pendiente lee de config; uno activo, de resolved_config congelado" do
      challenge = build_pipeline(%w[ideation evaluation], challenge_status: "draft")
      step = challenge.steps.find_by(kind: "evaluation")
      step.update!(config: { "min_assessments" => 2 })

      expect(step.settings["min_assessments"]).to eq(2)

      Flow::Handlers::Base.for(step).activate!
      step.reload
      expect(step.settings["min_assessments"]).to eq(2)

      # Cambiar config después NO afecta a un step ya activo: lee del snapshot.
      step.update_column(:config, { "min_assessments" => 99 })
      expect(step.reload.settings["min_assessments"]).to eq(2)
    end
  end
end
