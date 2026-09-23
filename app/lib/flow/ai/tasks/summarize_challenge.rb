# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # Resumen narrativo: qué temas emergieron, por qué ganaron las que
      # ganaron, qué se perdió en el camino.
      class SummarizeChallenge < Base
        def messages
          data = Flow::Reports::Builder.new(step).call

          [
            { role: "system", content: <<~TXT.squish },
              Escribís el cierre de un proceso de innovación para el equipo que lo corrió.
              Prosa clara, sin viñetas de relleno. Decís qué temas aparecieron, por qué las
              seleccionadas ganaron, y qué quedó afuera que valga la pena revisar.
            TXT
            { role: "user", content: <<~TXT }
              Desafío: #{challenge.name}
              Brief: #{challenge.brief}
              Embudo: #{data['funnel'].map { |f| "#{f['name']}: #{f['entered']} entraron, #{f['advanced']} avanzaron" }.join(' | ')}
              Ranking: #{data['ranking'].first(10).map { |r| "#{r['rank']}. #{r['title']} (#{(r['score'] * 100).round}%)" }.join(' | ')}
            TXT
          ]
        end

        def schema
          {
            "type" => "object",
            "required" => %w[summary themes],
            "properties" => {
              "summary" => { "type" => "string" },
              "themes" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "required" => %w[name count],
                  "properties" => {
                    "name" => { "type" => "string" },
                    "count" => { "type" => "integer" },
                    "note" => { "type" => "string" }
                  }
                }
              },
              "left_behind" => { "type" => "string" }
            }
          }
        end

        def target_attributes = { challenge_step: step }

        # Escribe el resumen del módulo de reportería. Casi siempre queda
        # tapado por el desafío cerrado —completar el último módulo lo cierra—
        # pero reportería no siempre es el último.
        def requires_active_step? = true

        def apply!(payload, suggestion:)
          Report.create!(
            challenge_step: step, kind: "narrative", format: "dashboard",
            status: "ready", data: payload, generated_at: Time.current,
            ai_run_id: suggestion.ai_run_id, scope: { "mode" => "latest" }
          )
          [true, []]
        end

        def preview(payload) = payload["summary"].to_s.truncate(220)
      end
    end
  end
end
