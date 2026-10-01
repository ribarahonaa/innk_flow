# frozen_string_literal: true

module Flow
  module Workshops
    # Entrar al taller escaneando su link. Sienta y marca presente.
    #
    # Es IDEMPOTENTE, y no por prolijidad: un link se escanea dos veces con los
    # dedos fríos, y la pantalla se recarga. La segunda vez marca presente y no
    # mueve a nadie — quien ya estaba convocado a la mesa 3 no termina en la
    # llegada por haber escaneado.
    class CheckIn
      ARRIVAL_NAME = "Mesa de llegada"

      Result = Data.define(:ok, :member, :errors) do
        def ok? = ok
      end

      def initialize(workshop, user)
        @workshop = workshop
        @user = user
      end

      def call
        return failure("Hay que elegir una persona.") if @user.nil?
        # Las dos guardas se repiten aunque el controller ya preguntó: entre que
        # la pantalla se sirvió y el formulario se envió, alguien pudo cerrar el
        # taller o apagar el modo. El que escribe es este servicio.
        return failure("Este taller no está abierto.") unless @workshop.open?
        return failure("Este taller no toma asistencia por link.") unless @workshop.registered_attendance?

        seated = seat_of(@user)
        return present!(seated) if seated

        result = Convoke.new(@workshop, @user, group: landing, attended: true).call
        return Result.new(ok: true, member: result.member, errors: []) if result.ok?

        # `Convoke` pudo fallar porque OTRO escaneo de la misma persona ganó la
        # carrera: los dos pasaron por `seat_of` en nil y el UNIQUE
        # (workshop_id, user_id) frenó al segundo. Para el check-in eso es éxito
        # —la persona está sentada— así que se resuelve por el mismo camino
        # idempotente de arriba. Propagar el fallo le diría «no entraste» a
        # alguien que entró, y el doble toque en un teléfono es lo más común que
        # le pasa a un QR.
        seated = seat_of(@user)
        return present!(seated) if seated

        Result.new(ok: false, member: nil, errors: result.errors)
      end

      private

      def present!(member)
        member.update!(attended: true)
        Result.new(ok: true, member: member, errors: [])
      end

      def seat_of(user)
        WorkshopGroupMember.joins(:workshop_group)
                           .where(workshop_groups: { workshop_id: @workshop.id }, user_id: user.id)
                           .first
      end

      # En modo individual NO hay mesa de llegada: `Convoke#own_group` arma la
      # mesa de una persona, que es el diseño de ese modo. Devolver `nil` es
      # pedirle exactamente eso.
      def landing
        return nil if @workshop.individual?

        @workshop.workshop_groups.find_or_create_by!(arrival: true) { |g| g.name = ARRIVAL_NAME }
      rescue ActiveRecord::RecordNotUnique
        # El índice UNIQUE parcial es justamente lo que un `find_or_create_by!`
        # no puede garantizar: es un SELECT y después un INSERT, y dos escaneos
        # en el mismo segundo lo atraviesan. Que la base frene al segundo es
        # correcto; lo que no corresponde es que quien está entrando vea un 500.
        @workshop.workshop_groups.find_by!(arrival: true)
      end

      def failure(message) = Result.new(ok: false, member: nil, errors: [message])
    end
  end
end
