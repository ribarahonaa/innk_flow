# frozen_string_literal: true

# «Sobre qué mesa estoy actuando»: una pregunta, un lugar.
#
# `Workshop#group_of` se queda significando «mi mesa» y la siguen preguntando
# los dos lugares donde eso es lo correcto —el panel «Mi mesa» de la pantalla
# del taller (el `@my_group` de `workshops#show`) y el camino sin administrar de
# `alcanzables` en las grabaciones—. Esto contesta
# la otra, y la consultan los cinco caminos de la sala.
#
# Escrita una vez a propósito: cinco caminos que resuelvan la mesa por su cuenta
# es la forma en que uno queda con `group_of(current_user)` y, sin fallar,
# **escribe en la mesa equivocada**.
module ActsOnAGroup
  extend ActiveSupport::Concern

  private

  # La mesa NOMBRADA gana, y el asiento propio es el FALLBACK. El orden sale del
  # modelo del dominio y no de la implementación: los únicos que se mueven entre
  # mesas son quien administra la empresa y el gestor, y ninguno de los dos
  # **participa** en una —se mueven para monitorear y dar feedback—, así que
  # para ellos no hay asiento propio que proteger y nombrar una mesa es la forma
  # normal de entrar a ella. Quien participa nunca se mueve solo: lo mueve quien
  # administra.
  #
  # Al revés —el asiento primero— quedaba un control que no responde: estando
  # sentado en una mesa, apretar «Entrar» en otra navegaba, cambiaba la URL y
  # dibujaba la mesa propia con el título «tu mesa», sin una palabra.
  #
  # El asiento propio sigue siendo lo que resuelve la entrada SIN parámetro, que
  # es la entrada de la mesa. Y para quien no administra ESE desafío el
  # parámetro se **ignora**, no se rechaza —un 403 confirmaría que esa mesa
  # existe—, así que para la mesa el orden no cambia nada: `named_group` le
  # devuelve `nil` y cae a su asiento igual.
  def acting_group(workshop, link)
    named_group(workshop, link) || own_group(workshop)
  end

  # Memoizado porque el GET de la sala lo puede preguntar dos veces: el fallback
  # de `acting_group` —sólo si no hay mesa nombrada— y el aviso de mesa ajena,
  # que compara una contra la otra y lo pregunta siempre. Ojo: la memoización no
  # mira `workshop`; asume UN solo taller por request, que es lo que vale hoy en
  # los cinco consumidores.
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
