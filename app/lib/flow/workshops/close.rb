# frozen_string_literal: true

module Flow
  module Workshops
    # Cerrar el taller cierra todos sus vínculos. Lo que quedó sin postular
    # sigue siendo borrador de su mesa: los `idea_contributors` persisten.
    class Close
      Result = Data.define(:ok, :errors) do
        def ok? = ok
      end

      def initialize(workshop, reason: "El taller se cerró.")
        @workshop = workshop
        @reason = reason
      end

      # Exige `open?` y devuelve un Result, igual que `Open`. Sin la guarda, un
      # POST sobre un taller en BORRADOR lo saltaba a `closed`, y como `Open`
      # exige `draft?` no se podía volver atrás nunca: un estado terminal sin
      # guarda no es una decisión de producto, es un bug de máquina de estados.
      def call
        return Result.new(ok: false, errors: [not_open]) unless @workshop.open?

        @workshop.with_lock do
          @workshop.workshop_challenges.where(status: "open").find_each do |link|
            link.update!(status: "closed", closed_at: Time.current, closed_reason: @reason)
          end
          @workshop.update!(status: "closed")
        end
        Result.new(ok: true, errors: [])
      end

      private

      def not_open
        return "Este taller ya está cerrado." if @workshop.closed?

        "Este taller todavía no se abrió: un borrador no se cierra, se elimina."
      end
    end
  end
end
