# frozen_string_literal: true

module Flow
  module Workshops
    # Cerrar el taller cierra todos sus vínculos. Lo que quedó sin postular
    # sigue siendo borrador de su mesa: los `idea_contributors` persisten.
    class Close
      def initialize(workshop, reason: "El taller se cerró.")
        @workshop = workshop
        @reason = reason
      end

      def call
        @workshop.with_lock do
          @workshop.workshop_challenges.where(status: "open").find_each do |link|
            link.update!(status: "closed", closed_at: Time.current, closed_reason: @reason)
          end
          @workshop.update!(status: "closed")
        end
        true
      end
    end
  end
end
