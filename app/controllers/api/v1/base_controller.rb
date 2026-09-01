# frozen_string_literal: true

module Api
  module V1
    # API JSON para las islas Vue. Hereda el mismo TenantResolution que el
    # resto: no hay un camino "de API" que se salte el aislamiento.
    class BaseController < ApplicationController
      protect_from_forgery with: :exception

      private

      def render_error(messages, status: :unprocessable_entity)
        render json: { errors: Array(messages) }, status: status
      end
    end
  end
end
