# frozen_string_literal: true

# «Sobre qué mesa estoy actuando»: una pregunta, un lugar.
#
# `Workshop#group_of` se queda significando «mi mesa» y la siguen preguntando
# los dos lugares donde eso es lo correcto —el panel «Mi mesa» de la pantalla
# del taller (`workshops_controller:84`) y el camino sin administrar de las
# grabaciones alcanzables (`workshop_recordings_controller:72`)—. Esto contesta
# la otra, y la consultan los cinco caminos de la sala.
#
# Escrita una vez a propósito: cinco caminos que resuelvan la mesa por su cuenta
# es la forma en que uno queda con `group_of(current_user)` y, sin fallar,
# **escribe en la mesa equivocada**.
module ActsOnAGroup
  extend ActiveSupport::Concern

  private

  # El asiento propio GANA SIEMPRE, y no es un detalle: es lo que hace que nada
  # de lo que ya funciona cambie de comportamiento —incluido el recorrido, cuyo
  # admin está sentado a propósito en el seed (`db/seeds.rb:857` y `:888`), de
  # lo que dependen `[DRAFT] 2` y `[GRABAR] 2`—.
  #
  # Si no hay asiento y quien mira administra ESE desafío, vale la mesa que
  # nombra el parámetro. Para todos los demás el parámetro se **ignora**, no se
  # rechaza: un 403 confirmaría que esa mesa existe.
  def acting_group(workshop, link)
    own_group(workshop) || named_group(workshop, link)
  end

  # Memoizado porque lo preguntan dos veces por render: `acting_group` y el
  # aviso de mesa ajena, que compara una contra la otra.
  def own_group(workshop)
    @own_group = workshop.group_of(current_user) unless defined?(@own_group)
    @own_group
  end

  def named_group(workshop, link)
    return nil if params[:mesa].blank?
    return nil unless policy(link.challenge).enter_any_group?

    workshop.group_named(params[:mesa])
  end
end
