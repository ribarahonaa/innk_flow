# frozen_string_literal: true

module Flow
  module Workshops
    # Convocar es sumar a una mesa. No hay una lista de convocados aparte:
    # dos fuentes para «quién está en este taller» divergen, y la primera vez
    # que difieran una de las dos estaría mintiendo.
    class Convoke
      Result = Data.define(:ok, :member, :errors) do
        def ok? = ok
      end

      def initialize(workshop, user, group: nil)
        @workshop = workshop
        @user = user
        @group = group
      end

      def call
        # Antes de crear nada: en modo individual, crear la mesa y recién
        # después chocar con la validación dejaría una mesa vacía colgada.
        return already_convoked if convoked?

        group = @group
        group ||= @workshop.individual? ? own_group : nil
        return group_required if group.nil?

        member = WorkshopGroupMember.new(workshop_group: group, user: @user)
        return Result.new(ok: true, member: member, errors: []) if member.save

        Result.new(ok: false, member: nil, errors: member.errors.full_messages)
      end

      private

      def convoked?
        WorkshopGroupMember.joins(:workshop_group)
                            .where(workshop_groups: { workshop_id: @workshop.id }, user_id: @user.id)
                            .exists?
      end

      # `users.name` es NOT NULL, así que siempre hay con qué nombrarla.
      def own_group = @workshop.workshop_groups.create!(name: @user.name)

      def already_convoked = Result.new(ok: false, member: nil, errors: ["Ya está en una mesa de este taller."])
      def group_required = Result.new(ok: false, member: nil, errors: ["Hay que elegir una mesa."])
    end
  end
end
