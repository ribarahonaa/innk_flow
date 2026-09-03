# frozen_string_literal: true

module Api
  module V1
    # Guardado completo del formulario, igual que el pipeline: llega la lista
    # entera y el server reconcilia.
    class FormFieldsController < BaseController
      before_action :set_context

      def show
        authorize @step, :manage_form?
        render json: payload
      end

      def update
        authorize @step, :manage_form?

        errors = apply_changes!
        return render_error(errors) if errors.any?

        render json: payload
      end

      private

      def set_context
        @challenge = policy_scope(Challenge).find_by!(slug: params[:challenge_slug])
        @step = @challenge.pipeline.ideation_step
        raise ActiveRecord::RecordNotFound if @step.nil?
      end

      # Con ideas ya postuladas, los cambios ESTRUCTURALES quedan bloqueados:
      # renombrar una clave o borrar un campo dejaría huérfanas las respuestas
      # que viven en el payload de cada versión. Lo cosmético sigue abierto.
      def locked? = @locked ||= @challenge.ideas.submitted.exists?

      def apply_changes!
        errors = []
        incoming = normalize_titles(Array(params[:fields]).map { |f| f.permit!.to_h.with_indifferent_access })

        ActiveRecord::Base.transaction do
          errors.concat(destroy_removed(incoming))
          errors.concat(upsert(incoming))
          raise ActiveRecord::Rollback if errors.any?
        end

        errors
      end

      # `PublishVersion` saca el título de la idea del campo marcado `is_title`,
      # con `detect`: si hay dos, el segundo es decoración muda. Se marca uno
      # solo —el primero que venga, o el primer campo si no vino ninguno— para
      # que lo que se guarda sea lo que se va a leer.
      def normalize_titles(incoming)
        flag = ->(f) { f[:is_title] == true || f[:is_title].to_s == "true" }
        chosen = incoming.index(&flag) || 0

        incoming.each_with_index { |field, index| field[:is_title] = (index == chosen) }
      end

      def destroy_removed(incoming)
        keep = incoming.filter_map { |f| f[:id].presence }
        removed = @step.form_fields.reject { |field| keep.include?(field.id) }
        return [] if removed.empty?

        if locked?
          return ["No se pueden quitar campos: ya hay ideas postuladas y sus respuestas " \
                  "quedarían huérfanas."]
        end

        removed.each(&:destroy)
        []
      end

      def upsert(incoming)
        incoming.each_with_index.filter_map do |attrs, index|
          field = attrs[:id].present? ? @step.form_fields.find_by(id: attrs[:id]) : @step.form_fields.new
          next if field.nil?

          field.label = attrs[:label]
          field.hint = attrs[:hint]
          field.required = attrs[:required].to_s == "true" || attrs[:required] == true
          field.position = index
          field.config = { "options" => Array(attrs[:options]).reject(&:blank?),
                           "is_title" => attrs[:is_title] == true }

          unless locked? && field.persisted?
            field.field_type = attrs[:field_type] if attrs[:field_type].present?
            field.key = attrs[:key] if attrs[:key].present?
          end

          next if field.save

          "«#{field.label.presence || 'campo sin nombre'}»: #{field.errors.full_messages.join(', ')}"
        end
      end

      def payload
        {
          fields: @step.form_fields.reload.ordered.map { |field| serialize(field) },
          fieldTypes: FormField::TYPES.map { |t| { value: t, label: I18n.t("flow.field_types.#{t}") } },
          locked: locked?,
          urls: {
            save: Rails.application.routes.url_helpers.api_v1_challenge_form_fields_path(@challenge),
            back: Rails.application.routes.url_helpers.builder_challenge_path(@challenge)
          }
        }
      end

      def serialize(field)
        {
          id: field.id, key: field.key, label: field.label, hint: field.hint,
          fieldType: field.field_type, required: field.required,
          isTitle: field.config["is_title"] == true,
          options: Array(field.config["options"]),
          answered: field.answered_count
        }
      end
    end
  end
end
