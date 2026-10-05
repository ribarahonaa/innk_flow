# frozen_string_literal: true

module Flow
  # Los dos nombres de tema que declara la hoja.
  #
  # Es una lista BLANCA, no una validación de formato: el valor sale de una
  # cookie —o sea de entrada del usuario— y se renderiza dentro de un atributo
  # del <html>. HAML escapa, así que no hay inyección; aceptar cualquier string
  # igual sería aceptar que el atributo diga cualquier cosa.
  module Themes
    NAMES = %w[flow flow-oscuro].freeze
  end
end
