# frozen_string_literal: true

module Flow
  module Workshops
    # Arma las mesas del taller: elige la ENTRADA según la fase y delega el
    # reparto en `Seating`, que no toca la base.
    class AssignGroups
      Result = Data.define(:ok, :tables, :splits, :errors) do
        def ok? = ok
      end

      def initialize(workshop, size:)
        @workshop = workshop
        @size = size
      end

      def call
        # En borrador los vínculos no tienen módulo, así que no hay fase con la
        # que elegir el criterio.
        return failure("El taller tiene que estar abierto para armar las mesas.") unless @workshop.open?
        # Rearmar mueve gente entre mesas y borra las que queden vacías, y
        # `workshop_proposals.workshop_group_id` es ON DELETE CASCADE: una mesa
        # con propuestas se llevaría las aceptadas, que son la procedencia de
        # versiones ya publicadas. Con trabajo hecho, se mueve a mano.
        return failure("Ya hay propuestas en este taller: las mesas se mueven a mano.") if proposals?

        grupos = @workshop.phase == "evolution" ? groups_by_idea : groups_by_person
        return failure("No hay a quién sentar.") if grupos.empty?

        seating = Seating.new(groups: grupos, size: @size).call
        @workshop.transaction { seat!(seating.tables) }

        Result.new(ok: true, tables: seating.tables, splits: seating.splits, errors: [])
      end

      private

      def proposals?
        WorkshopProposal.joins(:workshop_group)
                        .where(workshop_groups: { workshop_id: @workshop.id })
                        .exists?
      end

      # Evolución: un grupo por idea del módulo, con su gente. Los `step_entries`
      # y no `challenge.ideas`, porque el módulo trabaja lo que entró en él.
      def groups_by_idea
        ideas = Idea.where(id: StepEntry.where(challenge_step_id: open_step_ids).select(:idea_id)).alive
        por_idea = ideas.to_h { |idea| [idea.id, people_of(idea)] }
        # La regla de no evictar: quien ya está sentado y presente entra, aunque
        # no trabaje en ninguna idea. Sólo quien NO está en ninguna: sumar un
        # grupo de una persona que YA está en una idea no cambia las mesas —el
        # racimo las une y `personas` deduplica— pero sí agrega una clave que el
        # reparto puede elegir para desprender, y ahí el aviso anunciaría un
        # corte que no movió a nadie.
        sueltos = seated_present_ids - por_idea.values.flatten
        por_idea.merge(sueltos.to_h { |id| [id, [id]] })
      end

      # Idear: un grupo por persona. No hay ideas de las que deducir nada.
      def groups_by_person
        # `- absent_ids` también sobre `participant_ids`: ése no está filtrado por
        # asistencia, así que sin esto un participante marcado ausente volvía a
        # entrar por el pool automático.
        ids = (participant_ids | seated_present_ids) - absent_ids
        ids.to_h { |id| [id, [id]] }
      end

      # Los ausentes salen del pool en las DOS fases. En evolución no es un
      # extra: si alguien no vino, su idea pierde a esa persona y eso CAMBIA los
      # racimos. Ignorarlo dejaría mesas armadas alrededor de gente que no está.
      #
      # Sólo se descuenta a quien está marcado ausente: la asistencia existe
      # para quien está sentado, y a quien nunca se convocó se lo presume
      # presente.
      def people_of(idea)
        ([idea.author_id] + IdeaContributor.where(idea_id: idea.id).pluck(:user_id)) - absent_ids
      end

      def absent_ids
        @absent_ids ||= WorkshopGroupMember.where(attended: false).joins(:workshop_group)
                                           .where(workshop_groups: { workshop_id: @workshop.id })
                                           .pluck(:user_id)
      end

      def open_step_ids = @workshop.workshop_challenges.select(&:open?).map(&:challenge_step_id).compact

      def participant_ids
        Membership.where(company_id: @workshop.company_id, role: "participant").pluck(:user_id)
      end

      def seated_present_ids
        WorkshopGroupMember.presentes.joins(:workshop_group)
                            .where(workshop_groups: { workshop_id: @workshop.id })
                            .pluck(:user_id)
      end

      # Sienta a cada mesa. Mueve a los presentes, crea las mesas que falten y
      # borra SÓLO las que quedan vacías —seguro porque el guarda de propuestas
      # ya corrió—. Un ausente conserva su asiento, así que su mesa no queda
      # vacía y no se borra.
      def seat!(tables)
        existentes = @workshop.workshop_groups.order(:created_at).to_a

        tables.each_with_index do |user_ids, i|
          mesa = existentes[i] || @workshop.workshop_groups.create!(name: "Mesa #{i + 1}")
          WorkshopGroupMember.presentes.joins(:workshop_group)
                              .where(workshop_groups: { workshop_id: @workshop.id }, user_id: user_ids)
                              .destroy_all
          user_ids.each { |id| WorkshopGroupMember.create!(workshop_group: mesa, user_id: id) }
        end

        @workshop.workshop_groups.reload.each { |mesa| mesa.destroy! if mesa.workshop_group_members.empty? }
      end

      def failure(message) = Result.new(ok: false, tables: [], splits: [], errors: [message])
    end
  end
end
