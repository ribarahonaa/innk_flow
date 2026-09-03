# frozen_string_literal: true

module Flow
  module Handlers
    # «Evaluación»: puntúa cada idea del cohorte con los criterios del módulo.
    class Evaluation < Base
      DEFAULT_MIN_ASSESSMENTS = 1
      AGGREGATIONS = %w[mean median trimmed_mean].freeze

      # Criterios genéricos para cuando nadie configuró el módulo. Igual que
      # «Idear» siembra campos por defecto: la maqueta tiene que poder correr
      # de punta a punta sin obligar a configurar todo primero.
      DEFAULT_CRITERIA = [
        { key: "impacto", name: "Impacto", weight: 0.4, scale_type: "numeric",
          description: "Cuánto mueve la aguja si funciona.",
          scale_config: { "min" => 1, "max" => 10 }, position: 0 },
        { key: "factibilidad", name: "Factibilidad", weight: 0.35, scale_type: "numeric",
          description: "Qué tan realizable es con lo que hay.",
          scale_config: { "min" => 1, "max" => 10 }, position: 1 },
        { key: "esfuerzo", name: "Esfuerzo", weight: 0.25, scale_type: "numeric",
          description: "Cuánto cuesta llevarla adelante. Menos es mejor.",
          scale_config: { "min" => 1, "max" => 10, "direction" => "lower_better" }, position: 2 }
      ].freeze

      def can_activate?
        set = step.criteria_set
        return [true, []] if set.nil? # se siembra uno por defecto en activate!

        errors = set.validation_errors
        return [false, errors] if errors.any?

        [true, []]
      end

      def progress
        entries = step.step_entries.includes(:idea)
        done = entries.count { |entry| complete?(entry) }
        Progress.new(done: done, total: entries.size, label: "ideas evaluadas")
      end

      def can_complete?
        pending = step.step_entries.includes(:idea).reject { |e| complete?(e) }
        return [true, []] if pending.empty?

        [false, ["Faltan evaluaciones: #{pending.size} #{'idea'.pluralize(pending.size)} " \
                 "sin llegar a su mínimo de evaluaciones."]]
      end

      def complete?(entry) = assessments_for(entry.idea_id).size >= min_assessments_for(entry.idea)

      # El mínimo de una idea nunca puede pedir más evaluaciones de las que
      # existen: quien participa de la idea no la evalúa, así que si el módulo
      # pide 3 y hay 3 evaluadores y uno es el autor, esperar 3 dejaría el
      # módulo trabado para siempre.
      def min_assessments_for(idea)
        asignados = step.step_assignments.includes(:user).map(&:user)
        bloqueados = asignados.count { |u| idea.participates?(u) }

        # Solo baja para las ideas cuyos autores están entre quienes evalúan.
        # Sin nadie bloqueado no hay nada que descontar, y el módulo todavía
        # sin asignar tampoco justifica aflojar el mínimo.
        return min_assessments if bloqueados.zero?

        disponibles = asignados.size - bloqueados
        # La IA también evalúa, y no participa de ninguna idea.
        disponibles += 1 unless effective_ai_mode == "human"

        disponibles.clamp(1, min_assessments)
      end

      # Evaluación A CIEGAS: ver los puntajes de los demás antes de poner el
      # propio ancla el juicio, y con tres notas parecidas a la vista es difícil
      # no acomodarse. Se revelan al enviar la propia. Quien administra las ve
      # siempre: necesita saber cómo viene el módulo.
      def revealed_for?(idea_id, user:, manager: false)
        return true if manager || !step.active?

        assessments_for(idea_id).any? { |a| a.evaluator_id == user&.id }
      end

      def criteria_snapshot = settings["criteria"] || []

      # Con qué criterios va a correr el módulo, ANTES de activarlo.
      #
      # `criteria_snapshot` solo existe una vez congelado, así que sin esto no
      # hay forma de mostrarle a su dueño la ficha que van a ver quienes
      # evalúan mientras todavía puede cambiarla. Los genéricos se instancian
      # sin guardar: son los mismos que sembraría `before_resolve_config!`.
      def criteria_preview
        return criteria_snapshot.map { |c| [c, Criterion.find_by(id: c["id"])] } if step.touched?

        records = step.criteria_set&.active_criteria || generic_criteria
        records.map { |record| [record.to_snapshot, record] }
      end

      def generic_criteria
        DEFAULT_CRITERIA.map { |attributes| Criterion.new(source: "manual", **attributes) }
      end

      # Lo que el evaluador realmente completa: ni las fórmulas ni los checks
      # automáticos se preguntan.
      def scored_criteria = criteria_snapshot.select { |c| c["source"].nil? || c["source"] == "manual" }

      def automatic_criteria = criteria_snapshot.select { |c| c["source"] == "automatic" }
      def derived_criteria = criteria_snapshot.select { |c| c["source"] == "formula" }

      def min_assessments = settings.fetch("min_assessments", DEFAULT_MIN_ASSESSMENTS).to_i

      def assessments_for(idea_id)
        @assessments ||= step.assessments.current.submitted_ones.group_by(&:idea_id)
        @assessments.fetch(idea_id, [])
      end

      # Agregado del módulo para una idea. Es lo que lee la selección: siempre
      # un número en [0,1], sin importar de qué escalas vino.
      def recompute_entry!(entry)
        list = step.assessments.current.submitted_ones.where(idea_id: entry.idea_id).to_a
        scores = list.filter_map { |a| a.normalized_score&.to_d }

        entry.update!(
          status: scores.size >= min_assessments ? "done" : "in_progress",
          result: {
            "score" => aggregate(scores)&.to_f,
            "assessments_count" => list.size,
            "dispersion" => dispersion(scores)&.to_f,
            "per_criterion" => per_criterion(list),
            "recomputed_at" => Time.current.iso8601
          }
        )
        entry
      end

      protected

      # Congela los criterios en el módulo. Editar el set después NO puede
      # reescribir puntajes históricos: la matemática usa este snapshot.
      def resolve_config!
        before_resolve_config!
        super
        set = step.criteria_set
        step.resolved_config = step.resolved_config.merge(
          "criteria" => set ? set.active_criteria.map(&:to_snapshot) : [],
          "criteria_set_id" => set&.id,
          "min_assessments" => min_assessments,
          "evaluator_aggregation" => settings.fetch("evaluator_aggregation", "mean")
        )
      end

      def on_activate
        assign_evaluators!
        request_ai_assessments! if effective_ai_mode == "ai_auto"
      end

      # Antes de congelar el snapshot: si el módulo no tiene criterios, se le
      # arma un set INLINE (atado a este módulo, no a la biblioteca).
      def before_resolve_config!
        return if step.criteria_set

        set = CriteriaSet.create!(
          name: "Criterios de «#{step.name}»",
          scope: "inline",
          owner_step_id: step.id,
          description: "Set por defecto. Editalo o reemplazalo por uno de la biblioteca."
        )
        DEFAULT_CRITERIA.each { |attributes| set.criteria.create!(**attributes) }
        set.refresh_status!
        step.update_column(:criteria_set_id, set.id)
        step.reload
      end

      def on_complete
        step.step_entries.each { |entry| recompute_entry!(entry) }
      end

      private

      def aggregation = settings.fetch("evaluator_aggregation", "mean")

      def aggregate(scores)
        return nil if scores.empty?

        case aggregation
        when "median" then median(scores)
        when "trimmed_mean" then trimmed_mean(scores)
        else scores.sum / scores.size
        end
      end

      def median(scores)
        sorted = scores.sort
        mid = sorted.size / 2
        sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
      end

      # Descarta el extremo alto y el bajo: amortigua al evaluador que puntúa
      # todo en 10 o todo en 1.
      def trimmed_mean(scores)
        return aggregate_mean(scores) if scores.size < 3

        sorted = scores.sort[1..-2]
        sorted.sum / sorted.size
      end

      def aggregate_mean(scores) = scores.sum / scores.size

      def dispersion(scores)
        return nil if scores.size < 2

        mean = scores.sum / scores.size
        Math.sqrt(scores.sum { |s| (s - mean)**2 } / scores.size).to_d
      end

      def per_criterion(assessments)
        rows = AssessmentScore.where(assessment_id: assessments.map(&:id)).to_a
        rows.group_by(&:criterion_key).transform_values do |group|
          values = group.filter_map { |s| s.normalized_value&.to_d }
          values.empty? ? nil : (values.sum / values.size).to_f.round(4)
        end.compact
      end

      # En modo automático la IA cubre el mínimo del módulo: si pide 3
      # evaluaciones por idea, hace 3. Cada pasada es una consulta
      # independiente al proveedor —su propio ai_run— así que el promedio y la
      # dispersión significan algo, igual que con tres evaluadores humanos.
      #
      # Una llamada por pasada, encolada: nunca fan-out síncrono en el request.
      #
      # En `ai_assisted` no se dispara sola — la IA queda disponible como una
      # opinión más que alguien puede pedir, no como el evaluador por defecto.
      def request_ai_assessments!
        step.step_entries.each do |entry|
          faltan = min_assessments - assessments_for(entry.idea_id).size
          next if faltan <= 0

          faltan.times do |pass|
            Flow::AI::RunJob.perform_later(
              step.company_id, "evaluate_idea",
              { "step_id" => step.id, "idea_id" => entry.idea_id, "pass" => pass + 1 }
            )
          end
        end
      end

      # Todos los que pueden evaluar en la empresa, salvo que ya haya
      # asignaciones explícitas.
      #
      # find_or_create_by y no create!: activate! puede reintentarse desde un
      # job, y una asignación duplicada no debería tumbar la activación.
      def assign_evaluators!
        return if step.step_assignments.reload.any?

        Membership.where(role: %w[evaluator admin]).find_each do |membership|
          StepAssignment.find_or_create_by!(challenge_step_id: step.id, user_id: membership.user_id) do |assignment|
            assignment.role = "evaluator"
          end
        end

        notify_evaluators!
      end

      # Sin esto, a nadie le llega que le tocó trabajo: el módulo abre y espera
      # a que alguien entre a mirar por su cuenta.
      def notify_evaluators!
        pending = step.step_entries.size

        step.step_assignments.includes(:user).each do |assignment|
          Flow::Notifications::Notify.call(
            kind: "assigned_to_evaluate", user: assignment.user, step: step,
            payload: { step: step.name, challenge: challenge.name, count: pending }
          )
        end
      end
    end
  end
end
