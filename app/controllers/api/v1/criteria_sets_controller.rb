# frozen_string_literal: true

module Api
  module V1
    # Guardado completo del set, igual que el pipeline y el formulario: llega
    # la lista entera y el server reconcilia. Un solo camino de escritura.
    class CriteriaSetsController < BaseController
      before_action :set_criteria_set, only: %i[update]

      def create
        @set = CriteriaSet.new(scope: "library")
        authorize @set
        save_and_render
      end

      def update
        authorize @set
        return render_error(["esta versión ya fue reemplazada por otra"]) if @set.superseded?

        # Un set de biblioteca EN USO no se edita en el lugar: hay módulos sin
        # arrancar apuntándole y les cambiaría la vara sin avisar. Se guarda
        # sobre una versión nueva, y los que ya lo usaban siguen con la suya.
        @versionado = @set.library? && @set.in_use?

        save_and_render
      end

      private

      # Por `policy_scope`: un set `inline` de un desafío que no ves no existe.
      def set_criteria_set = @set = policy_scope(CriteriaSet).find(params[:id])

      def save_and_render
        errors = apply_changes!
        return render_error(errors) if errors.any?

        @set.refresh_status!
        render json: CriteriaSetPresenter.new(@set.reload, membership: current_membership).as_json
                                         .merge(versioned: @versionado.present?)
      end

      def incoming = @incoming ||= Array(params[:criteria]).map { |c| c.permit!.to_h.with_indifferent_access }

      # Un criterio con notas puestas ya significó algo: cambiarle el peso, la
      # escala o lo que verifica reescribiría el sentido de lo puntuado. Lo
      # cosmético (nombre, descripción) sigue abierto.
      def locked?
        return @locked if defined?(@locked)

        @locked = AssessmentScore.where(criterion_id: @set.criteria.map(&:id)).exists?
      end

      def apply_changes!
        errors = []

        ActiveRecord::Base.transaction do
          fork_version! if @versionado
          @set.assign_attributes(name: params[:name], description: params[:description])
          errors << @set.errors.full_messages.to_sentence unless @set.save

          errors.concat(destroy_removed) if errors.empty?
          errors.concat(upsert) if errors.empty?

          raise ActiveRecord::Rollback if errors.any?
        end

        errors
      end

      # Los criterios que llegan traen los ids de la versión anterior. La copia
      # los renueva pero conserva las claves, así que se traduce por clave y la
      # reconciliación de siempre (quitar, actualizar, crear) sigue andando.
      def fork_version!
        previos = @set.criteria.ordered.index_by(&:id)
        @set = @set.next_version!
        copias = @set.criteria.index_by(&:key)

        incoming.each do |attrs|
          origen = previos[attrs[:id]]
          attrs[:id] = origen ? copias[origen.key]&.id : nil
        end
      end

      def destroy_removed
        keep = incoming.filter_map { |c| c[:id].presence }
        removed = @set.criteria.reject { |c| keep.include?(c.id) }
        return [] if removed.empty?

        return ["No se pueden quitar criterios: ya hay evaluaciones hechas con este set."] if locked?

        removed.each(&:destroy)
        []
      end

      def upsert
        incoming.each_with_index.filter_map do |attrs, index|
          criterion = attrs[:id].present? ? @set.criteria.find_by(id: attrs[:id]) : @set.criteria.new
          next if criterion.nil?

          assign(criterion, attrs, index)
          next if criterion.save

          "«#{attrs[:name].presence || 'criterio sin nombre'}»: #{criterion.errors.full_messages.join(', ')}"
        end
      end

      def assign(criterion, attrs, index)
        criterion.name = attrs[:name]
        criterion.description = attrs[:description]
        criterion.position = index
        criterion.active = truthy(attrs[:active])

        return if locked? && criterion.persisted?

        criterion.source = attrs[:source]
        criterion.scale_type = attrs[:scale_type]
        # El peso viaja en porcentaje porque es lo que se edita; el dominio lo
        # guarda en [0,1], que es como lo lee el cálculo.
        criterion.weight = (attrs[:weight].to_f / 100.0).round(6)
        criterion.key = attrs[:key] if attrs[:key].present?
        criterion.source_config = clean_source_config(attrs)
        criterion.scale_config = clean_scale_config(attrs)
      end

      # Se guarda SOLO lo que la combinación elegida usa. Sin esto, cambiar de
      # verificación deja atrás los parámetros de la anterior y el config dice
      # cosas que ya no aplican.
      def clean_source_config(attrs)
        return {} unless attrs[:source] == "automatic"

        Flow::CriterionSettings.prune_check(attrs[:source_config].to_h, attrs.dig(:source_config, :check))
      end

      def clean_scale_config(attrs)
        Flow::CriterionSettings.prune_scale(attrs[:scale_config].to_h, attrs[:source], attrs[:scale_type])
      end

      def truthy(value) = value == true || value.to_s == "true"
    end
  end
end
