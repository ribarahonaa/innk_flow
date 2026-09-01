# frozen_string_literal: true

module Flow
  module Handlers
    # «Idear»: la generación de la idea. Único módulo no repetible — es la
    # creación del objeto que recorre el resto del flujo.
    #
    # Particularidad: es el único handler cuyo cohorte arranca VACÍO. Las
    # ideas nacen acá; los demás módulos las reciben.
    class Ideation < Base
      DEFAULT_MIN_IDEAS = 1

      # SIN FORMULARIO NO SE ARRANCA.
      #
      # Antes se sembraban tres campos por defecto acá adentro, al activar. Eso
      # dejaba al dueño sin ver nunca sus propias preguntas: nacían con el
      # desafío ya corriendo, cuando la ventana para cambiarlas ya se había
      # cerrado. Ahora el formulario se define antes, en /challenges/:id/form, y
      # el módulo se niega a abrir vacío en vez de inventar preguntas por su
      # cuenta.
      def can_activate?
        return [true, []] if step.form_fields.any?

        [false, ["«#{step.name}» no tiene formulario: nadie podría postular una idea. " \
                 "Definí las preguntas antes de arrancar."]]
      end

      def progress
        total = settings.fetch("min_ideas", DEFAULT_MIN_IDEAS).to_i
        done = submitted_ideas.count
        Progress.new(done: done, total: [total, done].max, label: "ideas postuladas")
      end

      def can_complete?
        minimum = settings.fetch("min_ideas", DEFAULT_MIN_IDEAS).to_i
        count = submitted_ideas.count
        return [true, []] if count >= minimum

        [false, ["Se necesitan al menos #{minimum} #{'idea'.pluralize(minimum)} postuladas (hay #{count})."]]
      end

      def submitted_ideas = challenge.ideas.submitted

      def draft_ideas_for(user) = challenge.ideas.where(author_id: user.id, status: "draft")

      def form_fields = step.form_fields.ordered

      protected

      def on_activate
        request_generated_ideas! if effective_ai_mode == "ai_auto"
      end

      # Al cerrar la postulación las ideas pasan a `active`: recién ahí entran
      # al cohorte de los módulos siguientes. Las que quedaron en borrador se
      # retiran — nunca se postularon.
      def on_complete
        challenge.ideas.submitted.where(status: "draft").find_each do |idea|
          idea.update!(status: "active")
          entry = StepEntry.find_or_initialize_by(challenge_step_id: step.id, idea_id: idea.id)
          entry.input_version_id ||= idea.current_version_id
          entry.entered_at ||= idea.submitted_at
          entry.assign_attributes(status: "advanced", output_version_id: idea.current_version_id,
                                  resolved_at: Time.current)
          entry.save!
        end

        challenge.ideas.where(status: "draft", submitted_at: nil).find_each do |idea|
          idea.update!(status: "withdrawn")
        end
      end

      private

      # En modo automático la IA genera las ideas al abrir el módulo, igual que
      # «Evolución» genera feedback y «Reportería» el resumen.
      #
      # En `ai_assisted` NO se dispara sola: ahí la IA acompaña a quien postula
      # (copiloto, duplicados) y generar candidatas queda como una acción que el
      # dueño pide desde la pantalla. Llenar el desafío de ideas sin que nadie
      # las pidiera sería invasivo.
      def request_generated_ideas!
        return if challenge.ideas.where(origin: "ai").exists?

        Flow::AI::RunJob.perform_later(
          step.company_id, "generate_ideas",
          { "step_id" => step.id, "count" => settings.fetch("generated_ideas", 5).to_i }
        )
      end
    end
  end
end
