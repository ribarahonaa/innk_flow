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

      # QUIÉN PUSO QUÉ. Dos razones para reservarlo:
      #
      #   · a ciegas — ver las notas de los demás antes de poner la propia
      #     ancla el juicio, y con tres números parecidos a la vista es difícil
      #     no acomodarse;
      #   · después del corte — que el autor lea el nombre de quien lo puntuó
      #     bajo y su comentario convierte un resultado en una discusión
      #     personal.
      #
      # Lo ve quien administra, y quien ya evaluó ESA idea.
      def breakdown_visible_for?(idea_id, user:, manager: false)
        return true if manager

        assessments_for(idea_id).any? { |a| a.evaluator_id == user&.id }
      end

      # EL PUNTAJE AGREGADO de una idea. Además de los anteriores, lo ve quien
      # participa de ella una vez cerrado el módulo: es su resultado, y saber
      # que salió 58 sin saber quién puso qué alcanza para entenderlo.
      def score_visible_for?(idea, user:, manager: false)
        return true if breakdown_visible_for?(idea.id, user: user, manager: manager)

        !step.active? && idea.participates?(user)
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
        # Cada nota con el peso de quien la puso. Sin pesos asignados son todos
        # 1 y la matemática es la de siempre.
        pares = list.filter_map { |a| [a.normalized_score.to_d, weight_of(a)] if a.normalized_score }

        entry.update!(
          # El mismo mínimo que usa `complete?`. Con el mínimo plano, la idea
          # cuyo autor evalúa quedaba "in_progress" para siempre aunque el
          # módulo la diera por completa.
          status: pares.size >= min_assessments_for(entry.idea) ? "done" : "in_progress",
          result: {
            "score" => aggregate(pares)&.to_f,
            "assessments_count" => list.size,
            "dispersion" => dispersion(pares)&.to_f,
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

      # El peso de una evaluación es el de quien la puso.
      #
      # La IA pesa 1: no se le asigna el módulo, es una opinión más. Y quien
      # evaluó sin estar asignado (se lo quitaron después, p.ej.) también: su
      # nota ya está puesta y no se la descuenta por un cambio posterior.
      def weight_of(assessment)
        return StepAssignment::DEFAULT_WEIGHT.to_d if assessment.evaluator_id.nil?

        assignment_weights.fetch(assessment.evaluator_id, StepAssignment::DEFAULT_WEIGHT.to_d)
      end

      def assignment_weights
        @assignment_weights ||= step.step_assignments.to_h { |a| [a.user_id, a.effective_weight] }
      end

      # Los pesos entran SOLO cuando alguien puso pesos distintos.
      #
      # No es una optimización: con todos iguales la mediana ponderada no
      # devuelve lo mismo que la mediana de siempre —con cantidad par, una
      # promedia los dos del medio y la otra devuelve el de abajo—. Que asignar
      # evaluadores sin tocar pesos cambie un puntaje ya calculado sería un
      # efecto que nadie pidió.
      def weighted?(pairs) = pairs.map(&:last).uniq.size > 1

      def aggregate(pairs)
        return nil if pairs.empty?

        scores = pairs.map(&:first)
        return plain_aggregate(scores) unless weighted?(pairs)

        case aggregation
        when "median" then weighted_median(pairs)
        when "trimmed_mean" then weighted_mean(trim_extremes(pairs))
        else weighted_mean(pairs)
        end
      end

      def plain_aggregate(scores)
        case aggregation
        when "median" then median(scores)
        when "trimmed_mean" then trimmed_mean(scores)
        else scores.sum / scores.size
        end
      end

      def weighted_mean(pairs)
        total = pairs.sum { |_score, weight| weight }
        return nil if total.zero?

        pairs.sum { |score, weight| score * weight } / total
      end

      # La nota donde el peso acumulado cruza la mitad: con pesos iguales es la
      # mediana de toda la vida (salvo el empate de cantidad par, que por eso
      # no pasa por acá).
      def weighted_median(pairs)
        sorted = pairs.sort_by(&:first)
        mitad = sorted.sum { |_score, weight| weight } / 2
        acumulado = 0

        sorted.each do |score, weight|
          acumulado += weight
          return score if acumulado >= mitad
        end

        sorted.last.first
      end

      # Mismo criterio que sin pesos: se van el más alto y el más bajo, no los
      # de más peso.
      def trim_extremes(pairs)
        return pairs if pairs.size < 3

        pairs.sort_by(&:first)[1..-2]
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

      # Ponderada también cuando el puntaje lo es: una dispersión calculada
      # sobre otra distribución que la del número que acompaña no describe
      # nada.
      def dispersion(pairs)
        return nil if pairs.size < 2

        scores = pairs.map(&:first)
        return plain_dispersion(scores) unless weighted?(pairs)

        mean = weighted_mean(pairs)
        total = pairs.sum { |_score, weight| weight }
        Math.sqrt(pairs.sum { |score, weight| weight * ((score - mean)**2) } / total).to_d
      end

      def plain_dispersion(scores)
        mean = scores.sum / scores.size
        Math.sqrt(scores.sum { |s| (s - mean)**2 } / scores.size).to_d
      end

      def per_criterion(assessments)
        pesos = assessments.to_h { |a| [a.id, weight_of(a)] }
        rows = AssessmentScore.where(assessment_id: assessments.map(&:id)).to_a

        rows.group_by(&:criterion_key).transform_values do |group|
          pairs = group.filter_map do |s|
            [s.normalized_value.to_d, pesos.fetch(s.assessment_id, 1.to_d)] if s.normalized_value
          end
          next nil if pairs.empty?

          (weighted?(pairs) ? weighted_mean(pairs) : pairs.sum(&:first) / pairs.size).to_f.round(4)
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
