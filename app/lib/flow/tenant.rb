# frozen_string_literal: true

module Flow
  # Control del tenant activo.
  #
  # `with` es la forma normal de entrar a una empresa (requests, jobs, seeds).
  # `bypass!` es la ÚNICA válvula de escape aceptada para saltar el scoping —
  # explícita, acotada a un bloque, y greppable. spec/lint/tenant_bypass_spec.rb
  # falla si aparece fuera de db/, lib/tasks/ o app/jobs/.
  #
  # Nunca usar `.unscoped` para lo mismo: es invisible en un grep y remueve
  # también los scopes de dominio, no solo el de tenancy.
  module Tenant
    BYPASS_KEY = :flow_tenant_bypass

    class << self
      def with(company)
        previous = Current.company
        Current.company = company
        yield
      ensure
        Current.company = previous
      end

      def bypassed?
        Thread.current[BYPASS_KEY].to_i.positive?
      end

      def bypass!
        Thread.current[BYPASS_KEY] = Thread.current[BYPASS_KEY].to_i + 1
        yield
      ensure
        Thread.current[BYPASS_KEY] = Thread.current[BYPASS_KEY].to_i - 1
      end
    end
  end
end
