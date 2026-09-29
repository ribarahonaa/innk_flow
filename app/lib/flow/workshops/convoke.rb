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
        # Primero de todo: un `user_id` vacío llega como `nil` desde el
        # controller (`User.find_by`). Sin esta guarda el servicio revienta con
        # `NoMethodError` en `convoked?`, que lee `@user.id`, antes de crear
        # nada; y aunque `convoked?` no existiera, en modo individual
        # `own_group` intentaría nombrar la mesa con `nil.name`.
        return person_required if @user.nil?

        # Antes de crear nada: en modo individual, crear la mesa y recién
        # después chocar con la validación dejaría una mesa vacía colgada.
        return already_convoked if convoked?

        group = @group
        group ||= @workshop.individual? ? own_group : nil
        return group_required if group.nil?

        member = WorkshopGroupMember.new(workshop_group: group, user: @user)
        return Result.new(ok: true, member: member, errors: []) if member.save

        Result.new(ok: false, member: nil, errors: member.errors.full_messages)
      rescue ActiveRecord::RecordNotUnique
        # El UNIQUE (workshop_id, user_id) es justamente lo que `convoked?` no
        # puede garantizar: es un `exists?` seguido de un `save`, y dos
        # convocatorias concurrentes lo atraviesan. Que la base frene a la que
        # llega segunda es lo correcto; lo que no corresponde es que salga un
        # 500. Es el mismo «ya está en una mesa» que la lectura habría dicho,
        # y vuelve por el mismo `Result` que el resto del servicio.
        already_convoked
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
      def person_required = Result.new(ok: false, member: nil, errors: ["Hay que elegir una persona."])
    end
  end
end
