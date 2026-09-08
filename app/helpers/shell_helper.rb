# frozen_string_literal: true

# Qué desafío manda en la pantalla, si es que hay alguno.
#
# La regla no es «qué controller es» sino «hay un desafío en contexto»: el
# flujo solo tiene sentido adentro de uno, y una barra lateral vacía sería un
# cuarto de pantalla que no dice nada.
#
# Tiene que estar GUARDADO. `/challenges/new` y el `create` que falla dejan un
# `@challenge = Challenge.new(...)` en la vista: sin slug, el `challenge_path`
# del drawer revienta con `UrlGenerationError` y la pantalla de crear un
# desafío se cae entera. Un desafío que todavía no existe tampoco tiene flujo
# que mostrar.
module ShellHelper
  def desafio_del_shell
    # Las pantallas de 404 y 403 se renderizan DESPUÉS del `Current.reset` del
    # around_action —`rescue_from` corre afuera de la cadena de callbacks—, así
    # que ahí no hay tenant. El drawer pide los módulos del desafío, que es una
    # consulta del dominio: sin este guard, cualquier 404 adentro de un desafío
    # revienta con MissingTenant al pintar el error. Y un error tampoco tiene
    # flujo que mostrar: no llegaste a ninguna parte.
    #
    # Pregunta por `Current.company` y no por el `current_company` del
    # controller a propósito: lo que hay que saber es si la consulta que viene
    # abajo puede correr, y eso lo decide el mismo lugar que mira el
    # `default_scope` de TenantScoped.
    return nil if Current.company.nil?

    candidato =
      if @challenge.is_a?(Challenge) then @challenge
      elsif @step.respond_to?(:challenge) then @step.challenge
      elsif @idea.respond_to?(:challenge) then @idea.challenge
      end

    candidato if candidato&.persisted?
  end
end
