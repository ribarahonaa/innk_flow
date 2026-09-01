# frozen_string_literal: true

module Flow
  # Qué ideas participan de un módulo.
  #
  # DECISIÓN: los step_entries se crean LAZY, al activar el step, y solo para
  # las ideas vivas. Nunca se pre-crean.
  #
  # Consecuencias, las tres deseables:
  #   · Una idea eliminada en una selección no genera fila en los módulos
  #     siguientes. `step_entries` significa exactamente "participación real",
  #     así que los reportes son COUNT(*) y no COUNT(*) WHERE status != '...'
  #     — la condición que alguien olvida y produce un reporte mal.
  #   · Agregar un módulo con ideas en vuelo no necesita backfill: el
  #     insertion floor garantiza que nace pending, y un step pending no tiene
  #     entries por definición.
  #   · La repesca crea la entry faltante en el momento, porque sync! es
  #     idempotente.
  #
  # Costo aceptado: "¿cuántas ideas llegan al módulo 5?" no es consultable
  # antes de activarlo. Es una proyección (`Cohort.for`), y la UI la rotula
  # como estimación.
  module Cohort
    class << self
      # Ideas que participarían de este módulo si se activara ahora.
      #
      # El módulo de ideación es el único cuyo cohorte arranca vacío: las
      # ideas nacen ahí, no llegan de antes.
      def for(step)
        return Idea.none if step.ideation?

        step.challenge.ideas.alive
      end

      # Idempotente: find_or_initialize_by + índice único (step_id, idea_id).
      # Esa idempotencia es lo que hace posible la repesca — volver a llamar
      # sync! sobre un step ya activo crea solo la entry que falta.
      def sync!(step)
        created = 0
        self.for(step).find_each do |idea|
          entry = StepEntry.find_or_initialize_by(challenge_step_id: step.id, idea_id: idea.id)
          next if entry.persisted?

          entry.input_version_id = idea.current_version_id
          entry.entered_at = Time.current
          entry.save!
          created += 1
        end
        created
      end
    end
  end
end
