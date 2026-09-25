# frozen_string_literal: true

module Flow
  # El motor del pipeline. Toda mutación del orden de los módulos pasa por acá.
  #
  # LA REGLA DEL PRODUCTO:
  #   Mientras el desafío está en borrador se puede agregar, reordenar y borrar
  #   libremente. Una vez que arrancó, se pueden seguir agregando módulos, pero
  #   SOLO a partir de la posición del último ya ejecutado o en curso. Nunca
  #   antes, nunca intercalado entre módulos ya realizados.
  #
  # Vive en #insertion_floor, y ChallengeStep la replica como validación de
  # modelo para que no se pueda saltear desde la consola.
  class Pipeline
    Result = Data.define(:ok, :step, :errors) do
      def ok? = ok
      def error_sentence = errors.join(". ")
    end

    Report = Data.define(:errors, :warnings) do
      def valid? = errors.empty?
      def any? = errors.any? || warnings.any?
    end

    STEP_SPACING = 1

    def initialize(challenge)
      @challenge = challenge
    end

    attr_reader :challenge

    # ── Lectura ────────────────────────────────────────────────────────────
    def steps = challenge.steps.ordered.to_a

    def active_step = steps.find { |s| s.active? || s.activating? }

    def next_pending = steps.find(&:pending?)

    def touched_steps = steps.select(&:touched?)

    def ideation_step = steps.find(&:ideation?)

    # ── La regla ───────────────────────────────────────────────────────────
    #
    # nil  => desafío en borrador: sin piso, todo es reordenable.
    # pos  => solo se puede colocar en positions ESTRICTAMENTE mayores.
    #
    # `skipped` cuenta: fue tocado aunque no se haya ejecutado, así que sube
    # el piso igual. Saltear un módulo no reabre la puerta a insertar antes.
    def insertion_floor(excluding: nil)
      return nil if challenge.draft?

      steps.reject { |s| excluding && (s == excluding || (excluding.id && s.id == excluding.id)) }
           .select(&:touched?)
           .map { |s| s.position.to_d }
           .max
    end

    def can_place_at?(position)
      floor = insertion_floor
      floor.nil? || position.to_d > floor
    end

    def can_remove?(step)
      step.pending? && can_place_at?(step.position)
    end

    # Reordenar los módulos PENDIENTES es legítimo aunque el flujo esté en
    # curso: la regla del producto limita dónde se puede COLOCAR algo (el
    # insertion floor), no prohíbe reacomodar lo que todavía no pasó.
    # #reorder aplica la regla fina: el prefijo ya tocado debe llegar intacto.
    def can_reorder? = !challenge.closed? && !challenge.archived?

    # Posición sugerida para un módulo nuevo al final del flujo.
    def next_position
      last = steps.map { |s| s.position.to_d }.max
      (last || 0) + STEP_SPACING
    end

    # ── Mutación ───────────────────────────────────────────────────────────
    #
    # `after: nil` = al final. `after: step` = inmediatamente después de ese.
    def insert(kind:, after: :end, **attributes)
      challenge.with_lock do
        position = position_after(after)
        step = challenge.steps.new(kind: kind, position: position, **attributes)

        return failure(step.errors.full_messages, step) unless step.save

        challenge.steps.reset
        success(step)
      end
    rescue ActiveRecord::RecordNotUnique => e
      failure(["conflicto de posiciones: #{e.message}"])
    end

    def move(step, after:)
      return failure(["el desafío está cerrado"]) unless can_reorder?
      return failure(["un módulo ya ejecutado no se puede mover"]) if step.touched?

      challenge.with_lock do
        step.position = position_after(after, excluding: step)
        return failure(step.errors.full_messages, step) unless step.save

        challenge.steps.reset
        success(step)
      end
    end

    def remove(step)
      return failure(["un módulo ya ejecutado no se puede quitar"]) unless can_remove?(step)

      challenge.with_lock do
        step.destroy!
        challenge.steps.reset
        success(step)
      end
    end

    # Guardado completo del builder: recibe el orden entero y renumera.
    #
    # Se revalida TODO en el server, incluido el floor. El cálculo del cliente
    # nunca se toma como palabra.
    def reorder(ordered_step_ids)
      challenge.with_lock do
        current = steps
        given = ordered_step_ids.map(&:to_s)

        if given.sort != current.map { |s| s.id.to_s }.sort
          return failure(["la lista de módulos no coincide con la del desafío"])
        end

        # El prefijo ya tocado no se puede reordenar: tiene que llegar en el
        # mismo orden en que se ejecutó.
        touched = current.select(&:touched?).map { |s| s.id.to_s }
        unless given.first(touched.size) == touched
          return failure(["los módulos ya ejecutados no se pueden reordenar ni desplazar"])
        end

        by_id = current.index_by { |s| s.id.to_s }
        renumber!(given.map { |id| by_id.fetch(id) })
        challenge.steps.reset
        success(nil)
      end
    end

    # Enteros contiguos 1..n. Se corre en cada guardado completo, así el
    # fraccional nunca degrada su precisión con el uso.
    def renumber!(ordered = steps)
      ordered.each_with_index do |step, index|
        target = (index + 1) * STEP_SPACING
        next if step.position.to_d == target

        # update_column: saltea las validaciones a propósito. La renumeración
        # es un movimiento en bloque coherente; validar fila por fila haría
        # fallar los estados intermedios contra el índice único de posición.
        step.update_column(:position, target)
      end
    end

    # ── Validación de armado ───────────────────────────────────────────────
    def validate
      errors = []
      warnings = []
      list = steps

      errors << "El desafío no tiene ningún módulo." if list.empty?
      errors << "Falta el módulo «Idear»: sin él no hay ideas que recorran el flujo." if list.none?(&:ideation?)

      list.select(&:selection?).each do |step|
        next if resolvable_score_source?(step, list)

        errors << "«#{step.name}» no tiene ninguna evaluación previa de la cual tomar puntaje."
      end

      if (ideation = list.find(&:ideation?)) && ideation.pending? && ideation.form_fields.empty?
        errors << "«#{ideation.name}» no tiene formulario: nadie podría postular una idea. " \
                  "Definí las preguntas desde la pantalla del módulo."
      end

      if (ideation = list.find(&:ideation?)) && list.first != ideation
        warnings << "«Idear» no es el primer módulo: los que están antes no van a recibir ideas."
      end

      list.each_cons(2) do |a, b|
        warnings << "«#{a.name}» y «#{b.name}» son dos selecciones seguidas: la segunda opera sobre el resultado de la primera." if a.selection? && b.selection?
      end

      warnings << "El flujo termina en «Evolución»: las ideas se actualizan pero nada las evalúa después." if list.last&.evolution?

      list.select { |s| s.evaluation? && s.pending? && s.criteria_set_id.blank? }.each do |step|
        warnings << "«#{step.name}» va a usar los criterios genéricos (impacto, factibilidad y " \
                    "esfuerzo). Desde la pantalla del módulo podés elegir un set de la biblioteca o " \
                    "definir los criterios propios de este módulo."
      end

      Report.new(errors: errors, warnings: warnings)
    end

    # ── Ejecución ──────────────────────────────────────────────────────────
    def start!
      return failure(["el desafío ya arrancó"]) unless challenge.draft?

      report = validate
      return failure(report.errors) unless report.valid?

      challenge.with_lock do
        challenge.update!(status: "running", started_at: Time.current)
        first = challenge.steps.ordered.first
        Flow::Handlers::Base.for(first).activate!
        success(first)
      end
    end

    def advance!
      current = active_step
      return failure(["no hay ningún módulo en curso"]) if current.nil?

      handler = Flow::Handlers::Base.for(current)
      ready, reasons = handler.can_complete?
      return failure(reasons) unless ready

      challenge.with_lock do
        handler.complete!
        open_next_or_close!
      end
    end

    # Abrir el siguiente módulo pendiente, o cerrar el desafío si no queda
    # ninguno. Es la cola de `advance!` sin su parte de cerrar el módulo en
    # curso, y es lo que necesita un SALTEO: `skip!` deja el módulo `skipped`,
    # o sea sin activo, y `advance!` entero no sirve ahí porque su primera
    # línea corta con `failure` exactamente en ese estado.
    #
    # `StepsController#skip` llamaba a `advance!` justo ahí, así que saltear el
    # módulo en curso dejaba el flujo trabado y sin avisar: el `if` de la
    # condición era verdadero y la llamada no podía hacer nada.
    def continue!
      challenge.with_lock { open_next_or_close! }
    end

    # Cerrar el desafío a mano, con el flujo donde esté.
    #
    # Saltea el módulo en curso, y no es prolijidad: dejándolo activo, el estado
    # del desafío y el del flujo se contradecían en la misma pantalla —el chip
    # decía «Cerrado», la tarjeta «Flujo» decía «ahora: X», y el mapa del flujo
    # y el drawer pintaban ese módulo como activo—. Arreglarlo en la vista
    # tapaba una de las tres caras.
    #
    # Salteado y no completado: no llegó a cerrarse por sus condiciones, lo
    # cortó el cierre del desafío, y el motivo queda escrito en el
    # `skip_reason`. Los pendientes no se tocan: nunca corrieron y su estado ya
    # lo dice.
    def close!
      challenge.with_lock do
        corriendo = active_step
        Flow::Handlers::Base.for(corriendo).skip!(reason: "se cerró el desafío") if corriendo
        challenge.update!(status: "closed", closed_at: Time.current)
        success(nil)
      end
    end

    private

    # Se llama SIEMPRE con el lock del desafío tomado: reordenar o cerrar
    # mientras otro proceso avanza el flujo es justo lo que el lock evita. Las
    # dos guardas van ACÁ y no en `continue!` por eso mismo: leídas afuera, dos
    # llamadas concurrentes veían las dos «no hay activo» y la segunda activaba
    # un módulo de más.
    #
    # `running?` no es de más. El `if active_step.nil?` que `skip` tenía
    # protegía sin querer algo más grande: en un desafío EN BORRADOR tampoco
    # hay módulo en curso, y ni `ChallengeStepPolicy#skip?` ni
    # `Handlers::Base#skip!` miran el estado del desafío, así que un salteo
    # autorizado sobre un borrador lo CERRABA —o le activaba un módulo adentro,
    # y con el desafío en borrador `insertion_floor` devuelve nil, o sea que el
    # builder pasaría a insertar antes de un módulo ya tocado—. Sacar el `if`
    # sin reponer la regla convirtió un arreglo en algo destructivo.
    def open_next_or_close!
      challenge.steps.reset
      return failure(["el desafío no está en curso"]) unless challenge.running?
      return failure(["hay un módulo en curso"]) if active_step

      following = challenge.steps.ordered.find(&:pending?)
      if following
        Flow::Handlers::Base.for(following).activate!
        return success(following)
      end

      challenge.update!(status: "closed", closed_at: Time.current)
      success(nil)
    end

    def resolvable_score_source?(step, list)
      source = step.settings.dig("score_source", "type")
      return true if source == "manual"

      index = list.index(step) || list.size
      list.first(index).any?(&:evaluation?)
    end

    # `after` puede ser :end (al final), nil (al principio) o un step.
    def position_after(after, excluding: nil)
      list = steps.reject { |s| excluding && s.id == excluding.id }

      case after
      when :end, "end"
        (list.map { |s| s.position.to_d }.max || 0) + STEP_SPACING
      when nil
        first = list.map { |s| s.position.to_d }.min
        first ? first / 2 : STEP_SPACING
      else
        anchor = after.is_a?(ChallengeStep) ? after : list.find { |s| s.id.to_s == after.to_s }
        raise ActiveRecord::RecordNotFound, "step de referencia inexistente" if anchor.nil?

        following = list.select { |s| s.position.to_d > anchor.position.to_d }
                        .min_by { |s| s.position.to_d }
        # Fraccional: una sola fila escrita, sin desplazar a nadie.
        following ? (anchor.position.to_d + following.position.to_d) / 2 : anchor.position.to_d + STEP_SPACING
      end
    end

    def success(step) = Result.new(ok: true, step: step, errors: [])
    def failure(errors, step = nil) = Result.new(ok: false, step: step, errors: Array(errors))
  end
end
