# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # La IA pone una idea a prueba contra situaciones concretas de ejecución
      # y dictamina si es factible.
      #
      # El rigor va en las SITUACIONES, no en el veredicto. Una IA crítica por
      # mandato dice «no factible» a casi todo; el filtro de la selección lo
      # consume y el desafío se queda sin finalistas. Por eso el prompt pide
      # buscar dónde se rompe, y al mismo tiempo ata el veredicto a lo que
      # encontró: `no_factible` sólo con una situación rota y un detalle
      # concreto, y si lo roto es arreglable, `con_reservas` con la condición
      # en `reservas`.
      class TestIdea < Base
        # Testear es de quien administra el desafío. Quien participa no testea
        # ni pide el testeo de su idea: con un solo testeo vigente donde el
        # último manda, pedirlo sería re-tirar el dado hasta que salga
        # «factible».
        def self.actua_sobre = :challenge

        def messages
          [
            { role: "system", content: <<~TXT.squish },
              Ponés una idea a prueba contra situaciones concretas de ejecución para decidir si
              es factible. Planteá situaciones donde la idea YA esté funcionando —un día puntual,
              un volumen, una persona que falta, un proveedor caído— y probá dónde se rompe.
              #{instruccion_de_severidad}
              El veredicto lo dicta lo que encontraste, no la actitud: poné no_factible sólo si
              al menos una situación se rompe y podés decir con qué detalle concreto; si lo que
              se rompe es arreglable, el veredicto es con_reservas y la condición a resolver va
              en reservas. Si nada se rompe, es factible. Una reserva es una condición a
              resolver, no una situación que falló.
            TXT
            { role: "user", content: <<~TXT }
              Desafío: #{challenge.name}
              Brief: #{challenge.brief}

              Idea: #{idea.title}
              #{idea.payload.map { |k, v| "#{k}: #{v}" }.join("\n")}

              Dimensiones que hay que cubrir: #{dimensiones.join(', ')}
              Mínimo de situaciones: #{handler.min_situations}
            TXT
          ]
        end

        def schema
          {
            "type" => "object",
            "required" => %w[situaciones veredicto reservas resumen],
            "properties" => {
              "situaciones" => {
                "type" => "array",
                "minItems" => handler.min_situations,
                # El mínimo se repite acá porque la API poda `minItems`: la
                # descripción es lo único que el modelo ve.
                "description" => "Al menos #{handler.min_situations} situaciones concretas de " \
                                 "la idea en ejecución.",
                "items" => {
                  "type" => "object",
                  "required" => %w[dimension escenario resultado detalle],
                  "properties" => {
                    # Enum con las dimensiones del módulo: el modelo no puede
                    # señalar una que nadie declaró.
                    "dimension" => { "type" => "string", "enum" => dimensiones },
                    "escenario" => { "type" => "string" },
                    "resultado" => { "type" => "string", "enum" => %w[aguanta se_rompe] },
                    "detalle" => { "type" => "string" }
                  }
                }
              },
              "veredicto" => { "type" => "string", "enum" => StepTest::VERDICTS },
              "reservas" => { "type" => "array", "items" => { "type" => "string" } },
              "resumen" => { "type" => "string" }
            }
          }
        end

        def target_attributes = { idea: idea }

        # Un veredicto de testeo es LA respuesta del módulo para esa idea y
        # habilita un filtro después: se propone y alguien lo acepta. Es el
        # criterio de `decide_verdicts`, no el de `evaluate_idea`.
        def applies_on_request? = false

        # Editado, un veredicto de la IA deja de serlo y sigue diciendo que lo
        # es. Es la lección de `EvaluateIdea`.
        def editable? = false

        def apply!(payload, suggestion:)
          handler.testear!(
            idea: idea,
            verdict: payload["veredicto"],
            situations: payload["situaciones"],
            reservations: Array(payload["reservas"]),
            summary: payload["resumen"],
            tested_by: nil,
            ai_run_id: suggestion.ai_run_id
          )

          [true, []]
        end

        def preview(payload)
          rotas = Array(payload["situaciones"]).select { _1["resultado"] == "se_rompe" }
          detalle = rotas.any? ? rotas.map { _1["escenario"] }.join(" · ") : "nada se rompió"

          "#{I18n.t("flow.verdicts.#{payload['veredicto']}")} — #{detalle}"
        end

        private

        def handler = step.handler
        def dimensiones = handler.dimensions

        def instruccion_de_severidad
          return "Probá lo previsible: las situaciones que la idea va a encontrar seguro." if
            handler.severity == "estandar"

          "Buscá activamente dónde se rompe: elegí las situaciones más exigentes que sean realistas."
        end
      end
    end
  end
end
