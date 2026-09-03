# frozen_string_literal: true

module Flow
  module AI
    module Tasks
      # Propone los criterios de UN módulo, ajustados al desafío.
      #
      # Es la configuración que más cuesta escribir a mano: hay que elegir los
      # dos ejes de cada criterio, repartir pesos que sumen 100 y, si el
      # criterio es automático, saber qué campo del formulario mirar.
      #
      # Los criterios propuestos son propios del módulo (`scope: inline`): una
      # propuesta nunca toca un set de la biblioteca, que comparten otros
      # desafíos.
      class SuggestCriteria < Base
        def messages
          [
            { role: "system", content: system_prompt },
            { role: "user", content: <<~TXT }
              Desafío: #{challenge.name}

              Brief: #{challenge.brief}

              Módulo: «#{step.name}» (#{I18n.t("flow.kinds.#{step.kind}")})

              #{form_briefing}
            TXT
          ]
        end

        # Una selección FILTRA y una evaluación PUNTÚA. Pedir lo mismo para las
        # dos da criterios que no sirven para ninguna.
        def system_prompt
          niveles = "Si un criterio usa rúbrica o letras, definí sus niveles con un descriptor " \
                    "que diga qué significa cada uno en este desafío."

          if step.selection?
            <<~TXT.squish
              Proponés los filtros de un módulo de selección: condiciones que una idea
              tiene que CUMPLIR para avanzar, no notas. Preferí criterios automáticos
              —que verifica el sistema sobre el formulario— y de sí/no que responde una
              persona. Entre 2 y 4 filtros. Los pesos suman 100.
            TXT
          else
            <<~TXT.squish
              Proponés los criterios con los que se puntúa cada idea de este desafío.
              Son específicos del problema del brief, no genéricos que servirían para
              cualquier empresa. Entre 3 y 5 criterios, con los pesos sumando 100: lo
              que más decide, más peso. Mezclá orígenes cuando aporte — algo que
              verifique el sistema evita discutir lo que se puede comprobar.
            TXT
          end
        end

        def schema
          {
            "type" => "object",
            "required" => %w[name criteria],
            "properties" => {
              "name" => { "type" => "string" },
              "description" => { "type" => "string" },
              "criteria" => {
                "type" => "array",
                "minItems" => 2,
                "maxItems" => 6,
                "items" => {
                  "type" => "object",
                  "required" => %w[name weight source],
                  "properties" => {
                    "name" => { "type" => "string" },
                    "description" => { "type" => "string" },
                    "weight" => { "type" => "number" },
                    # Sin `formula`: la expresión referencia las CLAVES de los
                    # criterios hermanos, que se derivan del nombre recién al
                    # guardar. El modelo no las puede conocer, y una fórmula
                    # vacía deja al set inválido. Se agregan a mano en el
                    # editor, donde las claves están a la vista.
                    "source" => { "enum" => Criterion::SOURCES - ["formula"] },
                    "scale_type" => { "enum" => Criterion::SCALE_TYPES },
                    "check" => { "enum" => Flow::CriterionSettings::CHECKS.keys },
                    "field_key" => { "enum" => field_keys.presence || [""] },
                    "minimum" => { "type" => "number" },
                    "min_length" => { "type" => "number" },
                    "expression" => { "type" => "string" },
                    "lower_is_better" => { "type" => "boolean" },
                    # Una rúbrica SIN descriptores propios es media rúbrica: el
                    # punto de elegirla es decirle a quien evalúa qué significa
                    # cada nivel en ESTE desafío.
                    "levels" => {
                      "type" => "array",
                      "items" => {
                        "type" => "object",
                        "required" => %w[label value descriptor],
                        "properties" => {
                          "label" => { "type" => "string" },
                          "value" => { "type" => "number" },
                          "descriptor" => { "type" => "string" }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        end

        def target_attributes = { challenge_step: step }

        def apply!(payload, suggestion:)
          return [false, ["el módulo ya se ejecutó: sus criterios quedaron congelados"]] if step.touched?

          set = build_set!(payload)
          errores = []
          guardados = []

          normalized(payload["criteria"]).each_with_index do |attrs, index|
            criterion = set.criteria.new(**criterion_attributes(attrs, index))
            if criterion.save
              guardados << criterion
            else
              errores << "«#{attrs['name']}»: #{criterion.errors.full_messages.join(', ')}"
            end
          end

          # Si alguno quedó afuera, los pesos ya no suman 100 y el set queda
          # inválido — el módulo no podría arrancar por culpa de un criterio
          # que ni siquiera existe. Se reparte entre los que sí entraron.
          rebalance!(guardados) if errores.any?

          set.refresh_status!
          step.update!(criteria_set_id: set.id)

          [true, errores]
        end

        def preview(payload)
          payload["criteria"].map { |c| "#{c['name']} #{c['weight'].to_i}%" }.join(" · ")
        end

        private

        def field_keys = answerable_fields.map(&:key)

        def answerable_fields
          ideation = challenge.pipeline.ideation_step
          return [] if ideation.nil?

          ideation.form_fields.ordered.reject { |f| f.field_type == "file" }
        end

        # Sin las claves REALES del formulario, un criterio automático apunta a
        # un campo que no existe y no lo puede cumplir nadie.
        def form_briefing
          return "El formulario todavía no tiene campos, así que no propongas criterios automáticos sobre campos." if answerable_fields.empty?

          "Campos del formulario que se pueden verificar:\n" +
            answerable_fields.map { |f| "- #{f.key}: «#{f.label}»" }.join("\n")
        end

        def build_set!(payload)
          CriteriaSet.create!(
            name: payload["name"].presence || "Criterios de «#{step.name}»",
            description: payload["description"],
            scope: "inline", owner_step_id: step.id
          )
        end

        # Los pesos llegan en 0-100 y el dominio los guarda en [0,1]. Se
        # renormalizan: si el modelo mandó 95 o 105, el set quedaría inválido
        # por un redondeo y no por un error de criterio.
        def normalized(criteria)
          total = criteria.sum { |c| c["weight"].to_f }
          return criteria if total.zero?

          criteria.map { |c| c.merge("weight" => (c["weight"].to_f / total)) }
        end

        def rebalance!(criteria)
          total = criteria.sum { |c| c.weight.to_d }
          return if total.zero?

          criteria.each { |c| c.update_column(:weight, (c.weight.to_d / total).round(6)) }
        end

        def levels?(attrs, scale) = %w[rubric letter].include?(scale) && attrs["levels"].present?

        # La `key` es lo que se guarda como respuesta; el label es lo que se
        # muestra. Se derivan del valor para que sean estables y ordenables.
        def levels_from(attrs)
          attrs["levels"].sort_by { |l| l["value"].to_f }.map do |level|
            { "key" => level["value"].to_i.to_s,
              "label" => level["label"].presence || level["value"].to_i.to_s,
              "value" => level["value"].to_i,
              "descriptor" => level["descriptor"] }
          end
        end

        def criterion_attributes(attrs, index)
          source = attrs["source"]

          { name: attrs["name"], description: attrs["description"],
            weight: attrs["weight"], position: index, source: source,
            scale_type: attrs["scale_type"].presence || "numeric",
            source_config: source_config_for(source, attrs),
            scale_config: scale_config_for(source, attrs) }
        end

        def source_config_for(source, attrs)
          return {} unless source == "automatic"

          config = { "check" => attrs["check"] }
          config["field_key"] = attrs["field_key"] if attrs["field_key"].present?
          config["min_length"] = attrs["min_length"].to_i if attrs["min_length"].present?
          config["minimum"] = attrs["minimum"].to_i if attrs["minimum"].present?

          Flow::CriterionSettings.prune_check(config, attrs["check"])
        end

        def scale_config_for(source, attrs)
          return { "expression" => attrs["expression"].to_s, "output" => { "min" => 0, "max" => 10 } } if source == "formula"
          return {} if source == "automatic"

          scale = attrs["scale_type"].presence || "numeric"
          config = Flow::CriterionSettings.scale_defaults(source, scale)
          config["direction"] = "lower_better" if attrs["lower_is_better"]
          config["levels"] = levels_from(attrs) if levels?(attrs, scale)
          config
        end
      end
    end
  end
end
