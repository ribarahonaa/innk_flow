# frozen_string_literal: true

module Flow
  module Handlers
    # «Selección»: reduce el pool. Solo avanzan las mejores.
    #
    # Nunca rehace matemática de evaluación: lee `step_entries.result["score"]`
    # de los módulos fuente, que siempre es un número en [0,1] sin importar si
    # la escala era 1-10, A-F o una fórmula.
    class Selection < Base
      CUT_MODES = %w[manual top_n top_percent threshold].freeze
      COMBINE_MODES = %w[weighted_avg max min last].freeze

      Row = Data.define(:idea, :entry, :score, :rank, :sources, :above_cut, :gates) do
        def above_cut? = above_cut
        def scored? = !score.nil?

        # Una idea avanza si pasa TODOS los filtros y además entra en el corte.
        def passes_gates? = gates.all? { |gate| gate[:passed] }
        def pending_gates = gates.select { |gate| gate[:passed].nil? }
        def failed_gates = gates.select { |gate| gate[:passed] == false }
        def eligible? = passes_gates? && above_cut?

        # Entró por el piso: avanza SIN pasar los filtros. Lo pregunta la
        # pantalla —una idea arriba de la línea con un ✗ al lado se lee como un
        # error de la app— y también la casilla del corte, que no se puede
        # deshabilitar por no pasar un filtro si igual va a avanzar.
        def por_el_piso? = above_cut && !passes_gates?
      end

      def can_activate?
        # Con filtros propios la selección se sostiene sola: no necesita una
        # evaluación previa para decidir quién pasa.
        #
        # Se mira el set ASIGNADO y no el snapshot: el snapshot se congela
        # recién en activate!, que es justamente lo que esto habilita.
        return [true, []] if step.criteria_set&.active_criteria&.any?
        return [true, []] if manual_source?
        return [true, []] if resolvable_sources.any?

        # Sin nombrarse: lo pone `Base#activate!`. Ojo que `Pipeline#validate`
        # tiene su propio texto para esto, con el nombre adentro, y ése no pasa
        # por el raise.
        [false, ["no tiene criterios propios ni una evaluación previa " \
                 "de la cual tomar puntaje"]]
      end

      # Los criterios del set asignado actúan como FILTROS: condiciones que la
      # idea tiene que cumplir para seguir. Los automáticos se verifican solos;
      # los de sí/no los responde una persona o la IA.
      def gate_criteria = settings["criteria"] || []

      # El criterio de un filtro y su descripción, UNA vez cada uno.
      #
      # `gates_for` corre por IDEA y ninguna de las dos cosas depende de la
      # idea, así que las dos se pedían una vez por filtro y por idea: el
      # criterio con un `find_by`, y la descripción caminando
      # `criterion.criteria_set.owner_step.challenge.pipeline.ideation_step` y
      # sus campos adentro de `FieldPresent#field_label`.
      #
      # Ojo con el TAMAÑO, porque medirlo lo corrigió: a la base llegaban 2
      # consultas a `criteria` y 1 a `form_fields`, no 10 y 8. La caché de
      # consultas de Rails sirve la repetición idéntica sin ir a la base, así
      # que el N+1 estaba en la FORMA del código y no en el costo. Se arregla
      # igual, porque esa caché existe sólo adentro de un request y este mismo
      # código en un job sí explotaría.
      #
      # Por lo mismo, NADA de esto lo puede pinchar un conteo de consultas: la
      # caché lo esconde. El conteo del spec cuida que el criterio se cargue una
      # vez; que la descripción también, no lo cuida nadie.
      #
      # Y no se resuelve leyendo el snapshot, que es lo que parece obvio:
      # `field_label` necesita la fila viva para llegar al formulario, así que un
      # `Criterion.new` armado con el snapshot degradaría «Título» a «titulo».
      def gate_criterion(id) = gate_criteria_records[id]

      def gate_criteria_records
        @gate_criteria_records ||= Criterion.where(id: gate_criteria.filter_map { |c| c["id"] }).index_by(&:id)
      end

      def gate_description(id)
        @gate_descriptions ||= {}
        return @gate_descriptions[id] if @gate_descriptions.key?(id)

        @gate_descriptions[id] = gate_criterion(id)&.check&.description
      end

      def automatic_gates = gate_criteria.select { |c| c["source"] == "automatic" }
      def verdict_gates = gate_criteria.select { |c| %w[manual ai].include?(c["source"]) }

      def verdicts_for(idea_id)
        @verdicts ||= SelectionVerdict.where(challenge_step_id: step.id).group_by(&:idea_id)
        @verdicts.fetch(idea_id, [])
      end

      # Registra el veredicto de una persona (o la IA) sobre un criterio.
      def record_verdict!(idea:, criterion_key:, passed:, decided_by: nil, note: nil, ai_run_id: nil)
        config = gate_criteria.find { |c| c["key"] == criterion_key }
        verdict = SelectionVerdict.find_or_initialize_by(
          challenge_step_id: step.id, idea_id: idea.id, criterion_key: criterion_key
        )
        verdict.assign_attributes(
          idea_version_id: idea.current_version_id, criterion_id: config&.dig("id"),
          passed: passed, decided_by: decided_by, actor_type: decided_by ? "human" : "ai",
          note: note, ai_run_id: ai_run_id
        )
        verdict.save!
        @verdicts = nil
        verdict
      end

      def progress
        decided = decisions_by_idea.keys.size
        Progress.new(done: decided, total: step.step_entries.size, label: "ideas resueltas")
      end

      def can_complete?
        reasons = []

        # Un filtro de veredicto sin responder deja a la idea en el limbo: no
        # se sabe si pasa o no.
        pending_verdicts = ranking.sum { |row| row.pending_gates.size }
        if pending_verdicts.positive?
          reasons << "#{Flow::Texto.faltan(pending_verdicts, "veredicto")} sobre los filtros."
        end

        if manual_cut?
          pending = step.step_entries.reject { |entry| decisions_by_idea.key?(entry.idea_id) }
          reasons << "Falta decidir sobre #{Flow::Texto.contar(pending.size, "idea")}." if pending.any?
        end

        [reasons.empty?, reasons]
      end

      # Tabla rankeada. Se calcula en lectura: persistirla sería estado
      # derivado que se desincroniza.
      def ranking
        rows = step.step_entries.includes(idea: %i[current_version author]).map do |entry|
          sources = source_scores_for(entry.idea_id)
          Row.new(idea: entry.idea, entry: entry, score: combine(sources),
                  rank: nil, sources: sources, above_cut: false, gates: gates_for(entry.idea))
        end

        # Las que no pasan los filtros van al fondo: el corte por puntaje se
        # aplica solo entre las que quedaron habilitadas.
        ordered = rows.sort_by do |row|
          [row.passes_gates? ? 0 : 1, row.score.nil? ? 1 : 0, -(row.score || 0), row.idea.created_at]
        end

        avanzan = quienes_avanzan(ordered)

        ordered.each_with_index.map do |row, index|
          Row.new(idea: row.idea, entry: row.entry, score: row.score, rank: index + 1,
                  sources: row.sources, above_cut: avanzan.include?(row.idea.id), gates: row.gates)
        end
      end

      # Estado de cada filtro para una idea: los automáticos se verifican en el
      # momento, los de veredicto se leen de lo que alguien ya decidió.
      def gates_for(idea)
        gate_criteria.map do |config|
          criterion = gate_criterion(config["id"])

          if config["source"] == "automatic"
            result = criterion&.verify(idea)
            { key: config["key"], name: config["name"], kind: :automatic,
              passed: result&.passed?, detail: result&.detail,
              description: gate_description(config["id"]) }
          else
            verdict = verdicts_for(idea.id).find { |v| v.criterion_key == config["key"] }
            { key: config["key"], name: config["name"], kind: :verdict,
              passed: verdict&.passed, detail: verdict&.note,
              decided_by: verdict&.decided_by_name,
              description: config["description"] }
          end
        end
      end

      # Aplica la decisión sobre un conjunto de ideas, en UNA transacción.
      # Es el único escritor de ideas.status y step_entries.status para este
      # módulo: la proyección no se puede desincronizar del log.
      def decide!(advancing_idea_ids, decided_by: nil, reason: nil)
        advancing = Array(advancing_idea_ids).map(&:to_s)
        rows = ranking.index_by { |row| row.idea.id }

        ActiveRecord::Base.transaction do
          step.step_entries.each do |entry|
            row = rows[entry.idea_id]
            advances = advancing.include?(entry.idea_id.to_s)

            record_decision!(entry.idea, outcome: advances ? "advance" : "eliminate",
                             rank: row&.rank, score: row&.score,
                             decided_by: decided_by, reason: reason)

            if advances
              entry.resolve!(status: "advanced", result: entry.result.merge("rank" => row&.rank))
              entry.idea.update!(status: "active", eliminated_at_step_id: nil)
            else
              entry.resolve!(status: "eliminated", result: entry.result.merge("rank" => row&.rank))
              entry.idea.update!(status: "eliminated", eliminated_at_step_id: step.id)
            end

            notify_outcome!(entry.idea, advances)
          end
        end
      end

      # Enterarse de que tu idea quedó fuera por entrar a mirar la tabla es la
      # peor forma de enterarse. Va a quien la creó y a quienes participaron.
      def notify_outcome!(idea, advanced)
        people = [idea.author] + idea.idea_contributors.includes(:user).map(&:user)

        people.uniq.each do |person|
          Flow::Notifications::Notify.call(
            kind: advanced ? "idea_advanced" : "idea_eliminated",
            user: person, step: step, idea: idea,
            payload: { idea: idea.title, step: step.name }
          )
        end
      end

      # Repesca: devuelve una idea eliminada al flujo.
      #
      # Escribe otra fila en el log (no edita la anterior), reactiva la idea y
      # le crea la entry del módulo activo — Cohort.sync! es idempotente, así
      # que solo aparece la que falta.
      def reinstate!(idea, decided_by: nil, reason: nil)
        ActiveRecord::Base.transaction do
          record_decision!(idea, outcome: "reinstate", decided_by: decided_by, reason: reason)
          idea.update!(status: "active", eliminated_at_step_id: nil)

          entry = step.step_entries.find_by(idea_id: idea.id)
          entry&.update!(status: "advanced", resolved_at: Time.current)

          active = challenge.pipeline.active_step
          Flow::Cohort.sync!(active) if active
        end
      end

      def eliminated_ideas
        challenge.ideas.where(status: "eliminated", eliminated_at_step_id: step.id)
                 .includes(:current_version, :author)
      end

      def source_steps
        ids = Array(settings.dig("score_source", "step_ids"))
        return [] if ids.empty?

        challenge.steps.select { |s| ids.include?(s.id) }
      end

      # Sin fuente de puntaje, el corte no ordena nada: avanzan todas las que
      # pasan los filtros.
      def no_score_source? = source_steps.empty?

      # Lo que la PANTALLA muestra, que no es lo mismo que lo que el corte usa.
      # `source_steps` sale de `resolved_config`, y eso recién se escribe en
      # `activate!`: en un módulo pendiente da siempre vacío. Mostrar eso hacía
      # que la ficha anunciara «sin fuente de puntaje: el orden es manual»
      # aunque hubiera una evaluación antes a la que el corte se ata solo al
      # arrancar. Acá se resuelve igual que en `resolve_config!`, sin escribir
      # nada: el late binding sigue pasando una sola vez y en su momento.
      def expected_source_steps
        return source_steps if step.touched?
        return [] if manual_source?

        resolve_source_steps(step.config["score_source"] || {})
      end

      def cut_mode = settings.dig("cut", "mode").presence || "manual"
      def cut_value = settings.dig("cut", "value").to_f
      def manual_cut? = cut_mode == "manual"

      # El nombre de la regla CON su número.
      #
      # `flow.cut_modes.top_n` sola dice «Top N», con la N de marcador:
      # impresa tal cual, la línea de corte del ranking decía el literal
      # «LÍNEA DE CORTE · TOP N» en vez del número que decide quién queda
      # afuera. La previsualización ya lo resolvía por su cuenta («avanzan las
      # 3 mejores»), así que había dos formas de nombrar lo mismo y sólo una
      # estaba bien.
      #
      # Es método de clase porque `Flow::Setup` arma la pista del drawer desde
      # `config` y ahí todavía no hay handler.
      def self.cut_rule_label(mode, value)
        I18n.t("flow.cut_modes.#{mode}", valor: value.to_f.to_i, default: mode.to_s)
      end

      def cut_rule_label = self.class.cut_rule_label(cut_mode, cut_value)

      # Cuántas ideas pasan como mínimo, pase lo que pase con la regla. 0 es
      # sin piso, que es como se comportaba esto antes de que existiera.
      def cut_min = settings.dig("cut", "min").to_i

      # ¿El piso levantó el corte por encima de lo que daba la regla sola?
      #
      # Lo pregunta la pantalla: sin decirlo, una idea aparece arriba de la
      # línea de corte con un puntaje que no alcanza y nadie entiende por qué.
      #
      # Recibe las filas ya calculadas porque `ranking` NO se memoiza a
      # propósito —`record_verdict!` invalida en el medio— y la pantalla ya lo
      # tiene: sin el parámetro, cada render lo calculaba dos veces, y ahí
      # adentro hay una consulta por criterio y por idea. Tiene que ser el
      # ranking ENTERO y no el filtrado por visibilidad: se cuenta cuántas
      # quedaron arriba del corte, y una lista recortada da de menos.
      def piso_aplicado?(filas = ranking)
        return false if cut_min.zero? || manual_cut? || no_score_source?

        elegibles = filas.select(&:passes_gates?)
        evaluadas = elegibles.count(&:scored?)
        # Lo que la regla SOLA dejaba pasar, contra lo que efectivamente pasó.
        # Con el piso cruzando los filtros el tope ya no es el subconjunto
        # elegible: comparar contra `[cut_min, evaluadas].min` decía que no
        # hubo piso justamente cuando el piso fue lo único que hizo avanzar a
        # alguien (con todas filtradas, `evaluadas` es cero).
        [cut_base(elegibles, evaluadas), evaluadas].min < filas.count(&:above_cut?)
      end

      protected

      def on_activate
        request_ai_verdicts! if effective_ai_mode == "ai_auto"
      end

      # En modo automático la IA responde los filtros de sí/no, que si no
      # quedan esperando a una persona y el módulo no cierra nunca. Una
      # consulta por idea —todos sus filtros de una— y encolada: nunca un
      # fan-out síncrono en el request.
      #
      # En `ai_assisted` no se dispara sola: un veredicto decide quién queda
      # afuera, así que la propone y alguien la acepta.
      def request_ai_verdicts!
        return if verdict_gates.empty?

        step.step_entries.each do |entry|
          Flow::AI::RunJob.perform_later(
            step.company_id, "decide_verdicts",
            { "step_id" => step.id, "idea_id" => entry.idea_id }
          )
        end
      end

      # Late binding: materializa `auto` a ids concretos, UNA sola vez.
      # Después de esto, reordenar el pipeline no puede cambiar de dónde sale
      # el puntaje de este módulo.
      def resolve_config!
        super
        freeze_criteria!
        source = (step.config["score_source"] || {}).deep_dup
        steps = source["type"].to_s == "manual" ? [] : resolve_source_steps(source)

        step.resolved_config = step.resolved_config.merge(
          "score_source" => {
            "type" => source["type"].presence == "manual" ? "manual" : "steps",
            "step_ids" => steps.map(&:id),
            "step_slugs" => steps.map(&:slug),
            "combine" => source["combine"].presence || "weighted_avg",
            "weights" => source["weights"] || {},
            "resolved_at" => Time.current.iso8601
          },
          "cut" => { "mode" => cut_mode_from_config, "value" => cut_value_from_config,
                     "min" => cut_min_from_config }
        )
      end

      private

      # Los filtros se congelan igual que en una evaluación: editar el set
      # después no puede cambiar retroactivamente quién pasó.
      def freeze_criteria!
        set = step.criteria_set
        step.resolved_config = step.resolved_config.merge(
          "criteria" => set ? set.active_criteria.map(&:to_snapshot) : [],
          "criteria_set_id" => set&.id
        )
      end

      def manual_source? = (step.config.dig("score_source", "type") || settings.dig("score_source", "type")) == "manual"

      # Regla de `auto`: la evaluación COMPLETADA más cercana hacia atrás.
      def resolvable_sources
        position = step.position.to_d
        challenge.steps.select { |s| s.evaluation? && s.position.to_d < position }
                 .sort_by { |s| -s.position.to_d }
      end

      def resolve_source_steps(source)
        slugs = Array(source["step_slugs"])
        return challenge.steps.select { |s| slugs.include?(s.slug) } if slugs.any?

        # Si el step de origen se eligió explícitamente por id (desde el
        # builder), se respeta.
        explicit = step.source_step
        return [explicit] if explicit

        Array(resolvable_sources.first)
      end

      def cut_mode_from_config
        mode = step.config.dig("cut", "mode").presence || "manual"
        CUT_MODES.include?(mode) ? mode : "manual"
      end

      def cut_value_from_config = step.config.dig("cut", "value").to_f
      def cut_min_from_config = step.config.dig("cut", "min").to_i

      def source_scores_for(idea_id)
        source_steps.each_with_object({}) do |source, acc|
          entry = source.step_entries.detect { |e| e.idea_id == idea_id }
          score = entry&.result&.dig("score")
          acc[source.slug] = score.to_f if score
        end
      end

      def combine(sources)
        return nil if sources.empty?

        case settings.dig("score_source", "combine")
        when "max" then sources.values.max
        when "min" then sources.values.min
        when "last" then sources.values.last
        else weighted_average(sources)
        end
      end

      def weighted_average(sources)
        weights = settings.dig("score_source", "weights") || {}
        return sources.values.sum / sources.size if weights.blank?

        total = sources.sum { |slug, _| (weights[slug] || 0).to_f }
        return sources.values.sum / sources.size if total.zero?

        sources.sum { |slug, score| score * (weights[slug] || 0).to_f } / total
      end

      # La regla decide cuántas pasan; el piso sube ese número si quedó corto, y
      # el total de evaluadas lo topea. El tope no es una precaución de más: sin
      # él un piso de 99 prometería 99 ideas sobre un pool de cinco. Es la misma
      # protección que `top_n` ya traía, ahora para los tres modos.
      def cut_size(ordered)
        return ordered.size if no_score_source?

        scored = ordered.count(&:scored?)
        [[cut_base(ordered, scored), cut_min].max, scored].min
      end

      # Quiénes quedan arriba del corte, en dos pasadas: la regla decide entre
      # las que pasaron los filtros, y si con eso avanzan menos que el mínimo,
      # el piso completa con las que no los pasaron.
      def quienes_avanzan(ordered)
        elegibles = ordered.select(&:passes_gates?)
        dentro = elegibles.select { |row| row.scored? || no_score_source? }.first(cut_size(elegibles))

        (dentro + relleno_del_piso(ordered, dentro.size)).map { |row| row.idea.id }.to_set
      end

      # El piso gana también sobre los FILTROS: si después de filtrar avanzan
      # menos ideas que el mínimo, se completa con las mejores puntuadas de las
      # que fallaron alguna condición. Sin esto, un corte en «IA automática»
      # cerraba el desafío con cero finalistas —justo lo que el piso existe
      # para evitar—, porque el mínimo se calculaba SOLO entre las que ya
      # habían pasado los filtros y los filtros lo bajaban en silencio.
      #
      # Un filtro sin responder no cuenta como fallado: no es un «no», es un
      # «todavía no», y completar con él daría por perdida una idea que nadie
      # miró. `can_complete?` ya traba el cierre hasta que alguien lo conteste.
      def relleno_del_piso(ordered, ya_avanzan)
        faltan = cut_min - ya_avanzan
        return [] if faltan <= 0 || manual_cut? || no_score_source?

        ordered.select { |row| !row.passes_gates? && row.pending_gates.empty? && row.scored? }
               .first(faltan)
      end

      def cut_base(ordered, scored)
        case cut_mode
        when "top_n" then [cut_value.to_i, scored].min
        when "top_percent" then (scored * cut_value / 100.0).ceil
        when "threshold" then ordered.count { |row| row.scored? && row.score >= cut_value }
        else scored
        end
      end

      def decisions_by_idea
        @decisions_by_idea ||= SelectionDecision.where(challenge_step_id: step.id)
                                                .latest_first.group_by(&:idea_id)
      end

      def record_decision!(idea, outcome:, rank: nil, score: nil, decided_by: nil, reason: nil)
        SelectionDecision.create!(
          challenge_step: step, idea: idea, idea_version_id: idea.current_version_id,
          outcome: outcome, rank: rank, score: score,
          decided_by: decided_by, actor_type: decided_by ? "human" : "ai",
          reason: reason, decided_at: Time.current
        )
        @decisions_by_idea = nil
      end

      # Al cerrar el módulo, si nadie decidió a mano, se aplica la regla.
      def on_complete
        return if decisions_by_idea.any?

        advancing = ranking.select(&:above_cut?).map { |row| row.idea.id }
        reason = gate_criteria.any? ? "Filtros + corte automático (#{cut_mode})" : "Corte automático (#{cut_mode})"
        decide!(advancing, reason: reason)
      end
    end
  end
end
