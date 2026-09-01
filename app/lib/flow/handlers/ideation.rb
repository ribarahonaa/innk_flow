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

      # Campos por defecto cuando nadie configuró el formulario. Deliberadamente
      # mínimos: la gracia es que el dueño (o la IA, en Fase 5) los defina.
      DEFAULT_FIELDS = [
        { key: "titulo", label: "Título", field_type: "text", required: true,
          config: { "is_title" => true }, position: 0 },
        { key: "problema", label: "¿Qué problema resuelve?", field_type: "textarea",
          required: true, position: 1 },
        { key: "solucion", label: "¿Cómo funcionaría?", field_type: "textarea",
          required: true, position: 2 }
      ].freeze

      def can_activate?
        return [true, []] if step.form_fields.any?

        # No se bloquea: se siembran los campos por defecto en activate!.
        [true, []]
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
        seed_default_fields! if step.form_fields.empty?
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

      def seed_default_fields!
        DEFAULT_FIELDS.each do |attributes|
          step.form_fields.create!(**attributes)
        end
      end
    end
  end
end
