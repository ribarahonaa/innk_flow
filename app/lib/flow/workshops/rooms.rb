# frozen_string_literal: true

module Flow
  module Workshops
    # Qué salas tiene un taller y si hay UNA sola a la que mandar a alguien.
    #
    # Existe por una sola razón: el redirect de `workshops#show` y el breadcrumb
    # de la sala tienen que preguntar lo mismo. Si el taller redirige a la sala,
    # un link «volver al taller» rebota en bucle; el breadcrumb lo evita
    # preguntando por `redirects?`, y una copia de esa condición escrita a mano
    # en la vista mentiría el día que una de las dos cambie.
    class Rooms
      def initialize(workshop)
        @workshop = workshop
      end

      # Precargado: el selector dibuja el nombre y el brief de cada desafío, y
      # `room_state` pregunta por el módulo de cada vínculo.
      def links
        @links ||= @workshop.workshop_challenges.includes(:challenge, :challenge_step).to_a
      end

      # `WORKABLE_KINDS` y no una lista nueva: las dos únicas fases sobre las
      # que un taller tiene algo que hacer ya están declaradas en el modelo.
      def workable
        @workable ||= links.select { |link| WorkshopChallenge::WORKABLE_KINDS.include?(link.room_state.to_s) }
      end

      def only_room = workable.size == 1 ? workable.first : nil

      # `can_assemble` entra como argumento y no se resuelve acá: es una
      # pregunta de Pundit sobre quien mira (`WorkshopPolicy#update?`), y esta
      # clase no conoce la membresía. Quien administra nunca se redirige
      # —el bloque de armado es lo que tiene que ver—.
      #
      # Y pide `links.one?` además de la sala única. El motivo del redirect es
      # «esta pantalla no tiene nada más que ofrecer», y una sala cerrada CON SU
      # MOTIVO sí es algo que ofrecer: con el redirect puesto sólo en «una sola
      # sala trabajable», quien no administra caía en la sala y el breadcrumb
      # —que pregunta esto mismo, para no hacer bucle— no le ofrecía volver, así
      # que no le quedaba NINGÚN camino al selector. Nunca se enteraba de que el
      # otro desafío estuvo en el taller ni de por qué cerró, que es justo lo
      # que el selector existe para no hacer.
      def redirects?(can_assemble:) = !can_assemble && !only_room.nil? && links.one?
    end
  end
end
