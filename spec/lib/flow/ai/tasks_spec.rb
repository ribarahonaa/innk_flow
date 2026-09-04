# frozen_string_literal: true

require "rails_helper"

RSpec.describe "tareas de IA" do
  let(:company) { without_tenant { create(:company) } }
  around { |example| as_company(company) { example.run } }

  let(:user) { without_tenant { create(:user) } }
  let(:challenge) { create(:challenge, name: "Merma", brief: "Reducir merma en bodega.") }
  let!(:step) { challenge.steps.create!(kind: "ideation", position: 1) }

  def run_task(task, mode: "ai_auto")
    Flow::AI::Runner.call(task, mode: mode, requested_by: user,
                                challenge: challenge, step: step)
  end

  describe Flow::AI::Tasks::SuggestFormFields do
    it "reemplaza el formulario con los campos propuestos" do
      step.form_fields.create!(key: "viejo", label: "Campo viejo")

      run_task(described_class.new(challenge: challenge, step: step))

      keys = step.form_fields.reload.ordered.map(&:key)
      expect(keys).to include("titulo", "problema", "solucion")
      expect(keys).not_to include("viejo")
      expect(step.form_fields.find_by(key: "titulo").config["is_title"]).to be(true)
    end

    it "NO toca el formulario si ya hay ideas postuladas" do
      # Cambiar los campos con respuestas cargadas dejaría payloads huérfanos.
      idea = create(:idea, challenge: challenge)
      Flow::Ideas::PublishVersion.new(idea, payload: { "x" => "y" }).call
      idea.update!(submitted_at: Time.current)
      step.form_fields.create!(key: "original", label: "Original")

      result = run_task(described_class.new(challenge: challenge, step: step))

      expect(result).not_to be_ok
      expect(step.form_fields.reload.map(&:key)).to eq(%w[original])
      expect(result.suggestion).to be_pending
    end
  end

  describe Flow::AI::Tasks::GenerateIdeas do
    before do
      step.form_fields.create!(key: "titulo", label: "Título", field_type: "text", config: { "is_title" => true })
      step.form_fields.create!(key: "problema", label: "Problema", field_type: "textarea")
      step.form_fields.create!(key: "solucion", label: "Solución", field_type: "textarea")
    end

    it "crea ideas marcadas origin: ai, ya postuladas" do
      expect { run_task(described_class.new(challenge: challenge, step: step)) }
        .to change { challenge.ideas.count }.by(Flow::AI::Tasks::GenerateIdeas::DEFAULT_COUNT)

      idea = challenge.ideas.reload.first
      expect(idea.origin).to eq("ai")
      expect(idea.submitted_at).to be_present
      expect(idea.current_version).to be_by_ai
      expect(idea.current_version.change_note).to eq("Generada por IA")
    end

    it "filtra el payload contra los campos del formulario" do
      run_task(described_class.new(challenge: challenge, step: step))

      expect(challenge.ideas.reload.first.payload.keys).to all(be_in(%w[titulo problema solucion]))
    end
  end

  describe Flow::AI::Tasks::CoauthorField do
    let(:field) { step.form_fields.create!(key: "solucion", label: "Solución", field_type: "textarea") }
    let(:idea) do
      i = create(:idea, challenge: challenge, author: user)
      Flow::Ideas::PublishVersion.new(i, payload: { "solucion" => "Poner sensores" }, author: user).call
      i
    end

    it "aceptar la sugerencia publica una VERSIÓN NUEVA, no pisa" do
      task = described_class.new(challenge: challenge, step: step, idea: idea, field: field)

      expect { Flow::AI::Runner.call(task, mode: "ai_auto", challenge: challenge, step: step, idea: idea) }
        .to change { idea.reload.versions.count }.by(1)

      expect(idea.current_version.payload["solucion"]).to match(/celdas de carga/)
      expect(idea.versions.first.payload["solucion"]).to eq("Poner sensores")
      expect(idea.current_version.change_note).to match(/Sugerencia de IA/)
    end

    it "en modo assisted no toca la idea hasta que alguien acepta" do
      task = described_class.new(challenge: challenge, step: step, idea: idea, field: field)
      result = Flow::AI::Runner.call(task, mode: "ai_assisted", challenge: challenge, step: step, idea: idea)

      expect(idea.reload.versions.count).to eq(1)

      Flow::AI::ApplySuggestion.new(result.suggestion, user: user).call

      expect(idea.reload.versions.count).to eq(2)
      expect(result.suggestion.reload).to be_accepted
      expect(result.suggestion.reviewed_by_id).to eq(user.id)
    end
  end

  describe Flow::AI::Tasks::DetectDuplicates do
    let(:idea) do
      i = create(:idea, challenge: challenge)
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores en racks" }).call
      i
    end

    it "no muta el dominio: es informativa" do
      create(:idea, challenge: challenge).tap do |other|
        Flow::Ideas::PublishVersion.new(other, payload: { "titulo" => "Otra cosa" }).call
      end

      task = described_class.new(challenge: challenge, step: step, idea: idea)
      expect { Flow::AI::Runner.call(task, mode: "ai_auto", challenge: challenge, idea: idea) }
        .not_to change { challenge.ideas.count }
    end

    it "usa embeddings, no #complete" do
      task = described_class.new(challenge: challenge, step: step, idea: idea)
      expect(task).to respond_to(:run_locally)

      result = Flow::AI::Runner.call(task, mode: "ai_assisted", challenge: challenge, idea: idea)
      expect(result).to be_ok
      expect(result.suggestion.payload).to have_key("matches")
    end

    it "una idea idéntica supera el umbral de similitud" do
      twin = create(:idea, challenge: challenge)
      Flow::Ideas::PublishVersion.new(twin, payload: { "titulo" => "Sensores en racks" }).call

      task = described_class.new(challenge: challenge, step: step, idea: idea)
      matches = task.run_locally(Flow::AI.provider)["matches"]

      expect(matches.map { _1["idea_id"] }).to include(twin.id)
      expect(matches.first["similarity"]).to be > 0.82
    end

    # Anthropic no tiene endpoint de embeddings: con el proveedor real este
    # botón levantaba ProviderUnsupported en la cara de quien lo apretaba.
    # Ahora ese caso tiene su propio camino, y encima explica el parecido.
    context "con un proveedor sin embeddings" do
      let!(:gemela) do
        create(:idea, challenge: challenge).tap do |i|
          Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Celdas de carga en los racks" }).call
        end
      end

      let(:proveedor) do
        Class.new(Flow::AI::Provider) do
          attr_accessor :respuesta
          attr_reader :llamadas

          def initialize = @llamadas = 0

          def embeddings? = false

          # La clase es anónima: sin esto Provider#name explota al derivarlo.
          def name = "stub"

          def complete(messages:, schema:, purpose:, temperature: 0.2)
            @llamadas += 1
            Flow::AI::Provider::Result.new(ok: true, data: respuesta, raw: respuesta, tokens_in: 120,
                                           tokens_out: 30, model: "stub", latency_ms: 5, error: nil)
          end
        end.new
      end

      around do |example|
        Flow::AI.provider = proveedor
        example.run
      ensure
        Flow::AI.reset_provider!
      end

      def correr
        Flow::AI::Runner.call(described_class.new(challenge: challenge, step: step, idea: idea),
                              mode: "ai_assisted", challenge: challenge, idea: idea)
      end

      it "le pregunta al modelo, que además explica el parecido" do
        proveedor.respuesta = {
          "matches" => [{ "idea_id" => gemela.id, "title" => gemela.title, "similarity" => 0.93,
                          "reason" => "Las dos miden peso por rack para detectar la diferencia." }]
        }

        result = correr

        expect(result).to be_ok
        expect(proveedor.llamadas).to eq(1)
        expect(result.suggestion.payload["matches"].first["reason"]).to be_present
        # Y los tokens de esa llamada quedan contados: el camino local los
        # reportaba en cero porque no había llamada que contar.
        expect(result.run.tokens_in).to eq(120)
      end

      # El modelo no puede señalar una idea que no existe ni una de otro
      # desafío: los ids posibles viajan en el schema.
      it "acota los ids posibles a las ideas de este desafío" do
        task = described_class.new(challenge: challenge, step: step, idea: idea)
        ids = task.schema.dig("properties", "matches", "items", "properties", "idea_id", "enum")

        expect(ids).to eq([gemela.id])
      end

      # Una idea eliminada SÍ es candidata —«esto ya se propuso y no avanzó»
      # es información útil— y la vista lo dice sin preguntarle al modelo.
      it "marca el estado de la idea con la que se parece" do
        gemela.update!(status: "eliminated")
        proveedor.respuesta = {
          "matches" => [{ "idea_id" => gemela.id, "title" => gemela.title, "similarity" => 0.9 }]
        }

        result = correr

        expect(result.suggestion.payload["matches"].first["idea_id"]).to eq(gemela.id)
        task = described_class.new(challenge: challenge, step: step, idea: idea)
        expect(task.preview(result.suggestion.payload)).to include("no avanzó")
      end

      it "sin nada con qué comparar no gasta una llamada" do
        gemela.destroy

        result = correr

        expect(result).to be_ok
        expect(proveedor.llamadas).to be_zero
        expect(result.suggestion.payload["matches"]).to be_empty
      end
    end
  end

  describe Flow::AI::Tasks::EvaluateIdea do
    let(:set) do
      s = CriteriaSet.create!(name: "Comité")
      s.criteria.create!(key: "impacto_negocio", name: "Impacto", weight: 1, source: "manual",
                         scale_type: "numeric", scale_config: { "min" => 1, "max" => 10 })
      s.refresh_status!
      s
    end
    let(:evaluation) { challenge.steps.create!(kind: "evaluation", position: 2, criteria_set: set) }
    let(:idea_a_evaluar) do
      i = create(:idea, challenge: challenge, status: "active")
      Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Una idea" }).call
      i.update!(submitted_at: Time.current)
      i
    end

    it "NO guarda una evaluación si la IA responde criterios que no existen en el set" do
      # El fixture responde impacto/factibilidad/esfuerzo; este set pide
      # impacto_negocio. Sin este chequeo se guardaba una evaluación con cero
      # scores que igual contaba para el mínimo, y el módulo cerraba con el
      # ranking vacío.
      Flow::Handlers::Base.for(evaluation).activate!
      task = described_class.new(challenge: challenge, step: evaluation.reload, idea: idea_a_evaluar)

      result = Flow::AI::Runner.call(task, mode: "ai_auto", challenge: challenge,
                                           step: evaluation, idea: idea_a_evaluar)

      expect(result).not_to be_ok
      expect(result.error_sentence).to match(/no evaluó ninguno de los criterios/)
      expect(evaluation.assessments.reload).to be_empty
      expect(result.suggestion.reload).to be_pending, "queda para que lo mire una persona"
    end
  end

  describe Flow::AI::ApplySuggestion do
    it "editar antes de aceptar guarda lo que REALMENTE se aplicó" do
      task = Flow::AI::Tasks::ProposePipeline.new(challenge: challenge)
      challenge.steps.destroy_all
      result = Flow::AI::Runner.call(task, mode: "ai_assisted", challenge: challenge)

      edited = { "rationale" => "Recortado a mano",
                 "steps" => [{ "kind" => "ideation", "name" => "Sólo idear" },
                             { "kind" => "reporting", "name" => "Reporte" }] }

      described_class.new(result.suggestion, user: user, payload: edited).call

      expect(result.suggestion.reload).to be_edited
      expect(result.suggestion.payload["rationale"]).to eq("Recortado a mano")
      expect(challenge.steps.reload.map(&:name)).to eq(["Sólo idear", "Reporte"])
    end

    it "rechazar no aplica nada" do
      task = Flow::AI::Tasks::ProposePipeline.new(challenge: challenge)
      challenge.steps.destroy_all
      result = Flow::AI::Runner.call(task, mode: "ai_assisted", challenge: challenge)

      described_class.new(result.suggestion, user: user).reject!(note: "No aplica")

      expect(result.suggestion.reload).to be_rejected
      expect(challenge.steps.reload).to be_empty
    end

    it "una sugerencia ya revisada no se aplica dos veces" do
      task = Flow::AI::Tasks::ProposePipeline.new(challenge: challenge)
      challenge.steps.destroy_all
      result = Flow::AI::Runner.call(task, mode: "ai_assisted", challenge: challenge)

      described_class.new(result.suggestion, user: user).call
      second = described_class.new(result.suggestion.reload, user: user).call

      expect(second).not_to be_ok
      expect(second.error_sentence).to match(/ya fue revisada/)
    end
  end
  # Un filtro de sí/no sin responder deja a la idea en el limbo y traba el
  # cierre del módulo. Antes solo lo podía responder una persona: una selección
  # en «Solo IA» no tenía cómo cerrarse.
  describe Flow::AI::Tasks::DecideVerdicts do
    let(:idea) do
      create(:idea, challenge: challenge).tap do |i|
        Flow::Ideas::PublishVersion.new(i, payload: { "titulo" => "Sensores por rack" }).call
        # Viva y postulada: es lo que hace que el cohorte de la selección la
        # incluya, y sin entry no hay filtro pendiente que responder.
        i.update!(submitted_at: Time.current, status: "active")
      end
    end

    let(:filtros) do
      set = CriteriaSet.create!(name: "Filtros de pase", scope: "library")
      set.criteria.create!(name: "El problema está claro", key: "problema_claro", weight: 0.5,
                           source: "manual", scale_type: "boolean",
                           description: "Se entiende qué se resuelve y para quién.")
      set.criteria.create!(name: "El piloto está acotado", key: "piloto_acotado", weight: 0.5,
                           source: "ai", scale_type: "boolean",
                           description: "Define alcance y plazo, no un despliegue completo.")
      set.refresh_status!
      set
    end

    let(:seleccion) do
      idea
      # Corte automático a propósito: así lo único que traba el cierre son los
      # veredictos, que es lo que este bloque prueba.
      paso = challenge.steps.create!(kind: "selection", position: 2, criteria_set: filtros,
                                     config: { "score_source" => { "type" => "manual" },
                                               "cut" => { "mode" => "top_n", "value" => 1 } })
      paso.handler.activate!
      paso
    end

    def decidir(mode: "ai_auto")
      Flow::AI::Runner.call(
        described_class.new(challenge: challenge, step: seleccion, idea: idea),
        mode: mode, requested_by: user, challenge: challenge, step: seleccion, idea: idea
      )
    end

    it "responde los filtros y queda el rastro de que los respondió la IA" do
      decidir

      veredictos = SelectionVerdict.where(challenge_step_id: seleccion.id, idea_id: idea.id)
      expect(veredictos.map(&:criterion_key)).to match_array(%w[problema_claro piloto_acotado])
      expect(veredictos.map(&:actor_type).uniq).to eq(["ai"])
      expect(veredictos.map(&:ai_run_id).compact.uniq.size).to eq(1)
      expect(veredictos.first.note).to be_present
    end

    it "así el módulo puede cerrar: sin veredictos no podía" do
      listo, razones = seleccion.handler.can_complete?
      expect(listo).to be(false)
      expect(razones.join).to include("veredicto")

      decidir

      expect(seleccion.reload.handler.can_complete?.first).to be(true)
    end

    # Quien puso un veredicto ya miró la idea y decidió. La IA no le pisa la
    # decisión ni siquiera cuando el módulo está en automático.
    it "no pisa el veredicto que puso una persona" do
      seleccion.handler.record_verdict!(idea: idea, criterion_key: "problema_claro",
                                        passed: false, decided_by: user, note: "No se entiende el alcance.")

      decidir

      humano = SelectionVerdict.find_by(challenge_step_id: seleccion.id, idea_id: idea.id,
                                        criterion_key: "problema_claro")
      expect(humano.passed).to be(false)
      expect(humano.actor_type).to eq("human")
      expect(humano.note).to eq("No se entiende el alcance.")
    end

    # Un veredicto decide quién queda afuera: no es una opinión más como una
    # evaluación, así que pedirlo no es aceptarlo.
    it "en modo asistido propone y espera revisión" do
      result = decidir(mode: "ai_assisted")

      expect(result).to be_ok
      expect(result.suggestion).to be_pending
      expect(SelectionVerdict.where(challenge_step_id: seleccion.id)).to be_empty

      expect(Flow::AI::ApplySuggestion.new(result.suggestion, user: user).call).to be_ok
      expect(SelectionVerdict.where(challenge_step_id: seleccion.id).count).to eq(2)
    end
  end
end

