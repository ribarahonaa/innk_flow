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
      step = challenge.steps.create!(kind: kind, position: index + 1, status: status || "pending")
      # Un módulo de ideación sin formulario no valida ni arranca. El helper le
      # da el mínimo para que los specs de acá hablen del pipeline y no del
      # formulario; el spec que prueba la falta lo arma aparte.
      seed_form!(step) if kind == "ideation"
    end
    challenge.update!(status: challenge_status)
    challenge.steps.reset
    challenge
  end

  # Un módulo que NO puede arrancar. `Evaluation#can_activate?` se niega con un
  # set sin criterios activos, y es el único «no está listo» que
  # `Pipeline#validate` no mira —mira el formulario de «Idear» y la fuente de
  # puntaje de una selección, no los errores del set—, así que es el que llega
  # hasta `activate!`.
  def with_broken_set!(step)
    set = CriteriaSet.create!(name: "Roto", scope: "library")
    set.refresh_status!
    step.update!(criteria_set: set)
    step
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

    # `activate!` levanta `StepNotReady` y no lo rescataba nadie: el pedido
    # moría con un 500.
    #
    # El rescate va AFUERA del `with_lock`, y esa posición es el diseño: acá la
    # excepción atraviesa la transacción, así que el `complete!` del módulo en
    # curso se DESHACE. Rescatarlo adentro lo dejaría completado y sin nadie
    # abierto, o sea el flujo trabado y sin control en ninguna vista para
    # destrabarlo.
    it "no completa el módulo en curso si el siguiente no puede arrancar" do
      challenge = build_pipeline(%w[ideation evaluation], challenge_status: "draft")
      pipeline = described_class.new(challenge)
      pipeline.start!
      with_broken_set!(challenge.steps.ordered.last)

      idea = create(:idea, challenge: challenge)
      Flow::Ideas::PublishVersion.new(idea, payload: { "titulo" => "Una idea" }).call
      idea.update!(submitted_at: Time.current)

      result = pipeline.advance!

      expect(result).not_to be_ok
      expect(result.error_sentence).to match(/al menos un criterio activo/)
      expect(challenge.steps.ordered.first.reload).to be_active
      expect(challenge.steps.ordered.last.reload).to be_pending
    end

    # `validate` no cubre este caso —mira el formulario y la fuente de puntaje,
    # no los errores del set—, así que arrancar con una evaluación adelante
    # también llegaba al 500.
    it "no arranca con un 500 si el primer módulo no puede activarse" do
      challenge = build_pipeline(%w[evaluation ideation], challenge_status: "draft")
      with_broken_set!(challenge.steps.ordered.first)

      result = described_class.new(challenge).start!

      expect(result).not_to be_ok
      expect(result.error_sentence).to match(/al menos un criterio activo/)
      expect(challenge.reload).to be_draft
      expect(challenge.steps.ordered.first.reload).to be_pending
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

  # Saltear el módulo en curso lo deja `skipped`, o sea sin módulo activo. Lo
  # que sigue —abrir el siguiente pendiente, o cerrar el desafío si no
  # queda— es la COLA de `advance!`, y `advance!` entero no se puede usar: su
  # primera línea corta con `failure` justo cuando no hay activo, que es el
  # estado que deja el salteo. `StepsController#skip` llamaba a `advance!` ahí,
  # así que saltear dejaba el flujo trabado sin que nada avisara.
  describe "#continue!" do
    it "abre el siguiente pendiente después de saltear el que estaba en curso" do
      challenge = build_pipeline(%w[ideation:skipped evaluation:pending reporting:pending])
      result = described_class.new(challenge).continue!

      expect(result).to be_ok
      expect(challenge.steps.ordered.second.reload).to be_active
      expect(challenge.reload).to be_running
    end

    it "cierra el desafío si no queda ninguno pendiente" do
      challenge = build_pipeline(%w[ideation:completed reporting:skipped])
      result = described_class.new(challenge).continue!

      expect(result).to be_ok
      expect(challenge.reload).to be_closed
    end

    # El `if active_step.nil?` que `skip` tenía protegía sin querer algo más
    # grande: en un desafío EN BORRADOR tampoco hay módulo en curso, así que
    # sin pedir `running?` un salteo autorizado sobre un borrador lo CERRABA
    # —o le activaba un módulo adentro, y con el desafío en borrador
    # `insertion_floor` devuelve nil, así que el builder insertaría antes de un
    # módulo ya tocado—. Ni la policy ni `skip!` miran el estado del desafío.
    it "no cierra un desafío en borrador" do
      challenge = build_pipeline(%w[reporting:skipped], challenge_status: "draft")
      result = described_class.new(challenge).continue!

      expect(result).not_to be_ok
      expect(challenge.reload).to be_draft
    end

    it "no activa un módulo adentro de un borrador" do
      challenge = build_pipeline(%w[ideation:skipped evaluation:pending], challenge_status: "draft")
      described_class.new(challenge).continue!

      expect(challenge.steps.ordered.second.reload).to be_pending
      expect(challenge.reload).to be_draft
    end

    # Acá el salteo YA se guardó en su propia transacción, así que no hay nada
    # que deshacer: queda salteado, el flujo no se mueve y el controller lo
    # dice con su rama de failure. Lo que se saca es el 500.
    it "avisa en vez de reventar si el siguiente pendiente no puede arrancar" do
      challenge = build_pipeline(%w[ideation:skipped evaluation:pending])
      with_broken_set!(challenge.steps.ordered.last)

      result = described_class.new(challenge).continue!

      expect(result).not_to be_ok
      expect(result.error_sentence).to match(/al menos un criterio activo/)
      expect(challenge.steps.ordered.first.reload).to be_skipped
      expect(challenge.steps.ordered.last.reload).to be_pending
      expect(challenge.reload).to be_running
    end

    # DOS evaluaciones, y ésa es toda la guarda: con una sola, cualquier mensaje
    # nombra la correcta por accidente y el ejemplo no distingue nada —el mismo
    # agujero que una fixture de posiciones 1, 2 y 3—. Los nombres se ponen a
    # mano porque `derive_name` le da a las dos el mismo por defecto.
    #
    # El nombre lo pone el sitio del `raise` y no el handler: los errores de una
    # evaluación salen de `CriteriaSet#validation_errors`, que no sabe de
    # módulos, así que `Evaluation#can_activate?` nunca se nombró y nada avisaba.
    it "dice QUÉ módulo no está listo, y no el otro" do
      challenge = create(:challenge, status: "draft")
      seed_form!(challenge.steps.create!(kind: "ideation", position: 1, status: "completed"))
      challenge.steps.create!(kind: "evaluation", position: 2, name: "Técnica", status: "completed")
      comite = challenge.steps.create!(kind: "evaluation", position: 3, name: "Comité")
      challenge.update!(status: "running")
      challenge.steps.reset
      with_broken_set!(comite)

      result = described_class.new(challenge).continue!

      expect(result).not_to be_ok
      expect(result.error_sentence).to include("«Comité»")
      expect(result.error_sentence).not_to include("«Técnica»")
      expect(result.error_sentence).to match(/al menos un criterio activo/)
    end

    # La otra mitad del cambio: `Ideation` y `Selection` dejaron de nombrarse a
    # sí mismas dentro de su razón, porque con el nombre puesto en el `raise`
    # quedaba duplicado. Esto lo cuenta.
    it "y lo nombra UNA vez, también cuando el motivo lo da el handler" do
      challenge = build_pipeline(%w[ideation:completed selection:pending])
      as_company(company) { challenge.steps.ordered.last.update!(name: "Corte") }
      challenge.steps.reset

      result = described_class.new(challenge).continue!

      expect(result).not_to be_ok
      expect(result.error_sentence.scan("«Corte»").size).to eq(1), result.error_sentence
      expect(result.error_sentence).to match(/no tiene criterios propios ni una evaluación previa/)
    end

    it "no toca nada si ya hay un módulo en curso" do
      challenge = build_pipeline(%w[ideation:active evaluation:pending])
      result = described_class.new(challenge).continue!

      expect(result).not_to be_ok
      expect(challenge.steps.ordered.second.reload).to be_pending
    end
  end

  # Cerrar un desafío a mano dejaba su módulo EN CURSO, y con eso el estado del
  # desafío y el del flujo se contradecían en la misma pantalla: el chip decía
  # «Cerrado» y la tarjeta «Flujo» decía «ahora: Reporte de cierre», y el mapa
  # del flujo y el drawer pintaban ese módulo como activo. Arreglarlo en la
  # vista tapaba una de las tres caras; la causa es que `close!` no cerraba lo
  # que estaba corriendo.
  describe "#close!" do
    it "saltea el módulo en curso: no queda nada corriendo en un desafío cerrado" do
      challenge = build_pipeline(%w[ideation:completed reporting:active])
      result = described_class.new(challenge).close!

      expect(result).to be_ok
      expect(challenge.reload).to be_closed
      expect(challenge.steps.ordered.reload.map(&:status)).to eq(%w[completed skipped])
      expect(described_class.new(challenge).active_step).to be_nil
    end

    it "deja constancia de por qué se salteó" do
      challenge = build_pipeline(%w[ideation:active])
      described_class.new(challenge).close!

      paso = challenge.steps.ordered.first.reload
      expect(paso.resolved_config["skip_reason"]).to eq("se cerró el desafío")
    end

    it "no toca los módulos si no había ninguno en curso" do
      challenge = build_pipeline(%w[ideation:completed reporting:pending])
      described_class.new(challenge).close!

      expect(challenge.reload).to be_closed
      expect(challenge.steps.ordered.reload.map(&:status)).to eq(%w[completed pending])
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
