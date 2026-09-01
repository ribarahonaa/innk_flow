# frozen_string_literal: true

module Api
  module V1
    # El builder guarda el pipeline COMPLETO en un PUT.
    #
    # El server revalida todo — orden, insertion floor, unicidad de ideación —
    # sin confiar en el cálculo del cliente. La UI que muestra la restricción y
    # el server que la impone son dos cosas distintas a propósito.
    class PipelinesController < BaseController
      before_action :set_challenge

      def show
        authorize @challenge, :builder?
        render json: presenter.as_json
      end

      def update
        authorize @challenge, :update_pipeline?

        # Bloqueo optimista: dos personas arrastrando a la vez no se pisan.
        if params[:lock_version].present? && params[:lock_version].to_i != @challenge.lock_version
          return render_error(
            "Otra persona modificó el flujo mientras editabas. Recargá la página.",
            status: :conflict
          )
        end

        errors = apply_changes!
        return render_error(errors) if errors.any?

        @challenge.reload
        render json: presenter.as_json
      end

      private

      def set_challenge
        @challenge = Challenge.find_by!(slug: params[:challenge_slug])
      end

      def presenter
        PipelinePresenter.new(@challenge.reload, membership: current_membership)
      end

      # El payload trae la lista entera de steps en su orden final. Se resuelve
      # como tres operaciones: borrar los que ya no están, crear los nuevos,
      # y reordenar/actualizar el resto.
      def apply_changes!
        errors = []
        pipeline = @challenge.pipeline
        incoming = Array(params[:steps]).map { |s| s.permit!.to_h.with_indifferent_access }

        ActiveRecord::Base.transaction do
          errors.concat(destroy_removed(pipeline, incoming))
          errors.concat(create_added(pipeline, incoming))
          errors.concat(update_existing(incoming))
          errors.concat(reorder_all(incoming))

          raise ActiveRecord::Rollback if errors.any?

          @challenge.increment!(:lock_version)
        end

        errors
      end

      def destroy_removed(pipeline, incoming)
        keep = incoming.filter_map { |s| s[:id].presence }
        pipeline.steps.reject { |step| keep.include?(step.id) }.filter_map do |step|
          result = pipeline.remove(step)
          "«#{step.name}»: #{result.error_sentence}" unless result.ok?
        end
      end

      def create_added(pipeline, incoming)
        incoming.reject { |s| s[:id].present? }.filter_map do |attrs|
          after = anchor_for(incoming, attrs)
          result = pipeline.insert(
            kind: attrs[:kind],
            after: after,
            name: attrs[:name].presence,
            ai_mode: attrs[:aiMode].presence,
            config: attrs[:settings].presence || {}
          )
          # El id provisional del cliente se reemplaza por el real.
          attrs[:id] = result.step&.id if result.ok?
          result.error_sentence unless result.ok?
        end
      end

      # Un step nuevo se ancla al último existente que lo precede en la lista
      # entrante; si no hay ninguno, va al principio.
      def anchor_for(incoming, attrs)
        index = incoming.index(attrs)
        previous = incoming.first(index).reverse.find { |s| s[:id].present? }
        return nil if previous.nil?

        @challenge.steps.find { |s| s.id == previous[:id] }
      end

      def update_existing(incoming)
        incoming.filter_map do |attrs|
          next if attrs[:id].blank?

          step = @challenge.steps.reload.find { |s| s.id == attrs[:id] }
          next if step.nil? || step.touched?

          step.name = attrs[:name] if attrs.key?(:name) && attrs[:name].present?
          step.ai_mode = attrs[:aiMode].presence
          step.config = attrs[:settings] if attrs.key?(:settings)
          step.source_step_id = attrs[:sourceStepId].presence
          next if step.save

          "«#{step.name}»: #{step.errors.full_messages.join(', ')}"
        end
      end

      def reorder_all(incoming)
        ids = incoming.filter_map { |s| s[:id].presence }
        current = @challenge.steps.reload
        return [] if ids.size != current.size
        return [] if ids == current.ordered.map(&:id)

        # No se filtra por can_reorder?: Pipeline#reorder aplica la regla fina
        # (el prefijo ya ejecutado debe llegar intacto), que permite reordenar
        # los módulos pendientes aunque el desafío esté en curso. Y si el
        # reorden es ilegal, DEVUELVE ERROR en vez de ignorarlo en silencio.
        result = @challenge.pipeline.reorder(ids)
        result.ok? ? [] : [result.error_sentence]
      end
    end
  end
end
