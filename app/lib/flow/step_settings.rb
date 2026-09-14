# frozen_string_literal: true

module Flow
  # Qué se puede configurar en cada tipo de módulo.
  #
  # FUENTE ÚNICA. El builder no declara campos: los renderiza a partir de esto,
  # así que sumar una opción es agregar una línea acá y no tocar Vue. Antes el
  # panel exponía 4 opciones de las 13 que los handlers leían, y las cajas de
  # Evolución y Reportería no tenían nada que configurar.
  #
  # `essential` va a la vista; `advanced` detrás de un desplegable.
  #
  # Los campos con `column: true` no viven en `config` sino en una columna del
  # step (el set de criterios, el módulo del que toma el puntaje).
  module StepSettings
    SCHEMA = {
      "ideation" => {
        essential: [
          { key: "min_ideas", type: "number", default: 1, min: 1,
            label: "Ideas mínimas para poder avanzar",
            hint: "El módulo no se cierra con menos ideas postuladas." }
        ],
        advanced: [
          { key: "generated_ideas", type: "number", default: 5, min: 1, max: 20,
            label: "Cuántas ideas genera la IA",
            hint: "Solo aplica cuando el módulo está en IA automática." }
        ]
      },

      "evolution" => {
        essential: [
          { key: "require_response", type: "boolean", default: false,
            label: "Exigir que cada idea responda",
            hint: "Si está activo, el módulo no se cierra hasta que todas publiquen una versión nueva." }
        ],
        advanced: []
      },

      "evaluation" => {
        # `criteria_set_id` NO vive acá: se elige en el bloque de criterios del
        # panel, junto a la opción de definir los propios del módulo. Tenerlo
        # como un campo suelto más dejaba dos lugares para lo mismo.
        essential: [
          { key: "min_assessments", type: "number", default: 1, min: 1,
            label: "Evaluaciones mínimas por idea",
            hint: "En IA automática, la IA hace las que falten para llegar a este número." }
        ],
        advanced: [
          { key: "evaluator_aggregation", type: "select", default: "mean",
            label: "Cómo se combinan las evaluaciones",
            options: [
              { value: "mean", label: "Promedio" },
              { value: "median", label: "Mediana" },
              { value: "trimmed_mean", label: "Promedio sin extremos" }
            ],
            hint: "«Sin extremos» descarta la nota más alta y la más baja: amortigua al que puntúa todo en 10." }
        ]
      },

      "selection" => {
        essential: [
          { key: "source_step_id", type: "select", column: true, source: "previous_evaluations",
            label: "Puntaje que usa para ordenar",
            blank: "Automático (la evaluación previa más cercana)",
            hint: "De qué módulo de evaluación toma la nota." },
          { key: "cut.mode", type: "select", default: "manual",
            label: "Regla de corte",
            options: [
              { value: "manual", label: "Manual: el dueño decide" },
              { value: "top_n", label: "Top N ideas" },
              { value: "top_percent", label: "Top N %" },
              { value: "threshold", label: "Puntaje mínimo" }
            ] },
          { key: "cut.value", type: "number", default: 10, min: 1,
            label: "Valor del corte",
            depends_on: { key: "cut.mode", not: "manual" } },
          { key: "cut.min", type: "number", default: 0, min: 0,
            label: "Mínimo de ideas que pasan",
            depends_on: { key: "cut.mode", not: "manual" },
            hint: "0 es sin piso. Cuando hay piso GANA sobre la regla: con «puntaje mínimo 0,8» " \
                  "y piso 3 pasan las 3 mejores aunque ninguna llegue a 0,8. Existe para que un " \
                  "corte en IA automática no deje el desafío sin finalistas. Nunca pasan más " \
                  "ideas de las que hay evaluadas." }
        ],
        advanced: [
          { key: "score_source.combine", type: "select", default: "weighted_avg",
            label: "Si combina varias evaluaciones",
            options: [
              { value: "weighted_avg", label: "Promedio ponderado" },
              { value: "max", label: "La nota más alta" },
              { value: "min", label: "La nota más baja" },
              { value: "last", label: "La última evaluación" }
            ] }
        ]
      },

      "reporting" => {
        essential: [
          { key: "mode", type: "select", default: "by_version",
            label: "Cómo trata las versiones",
            options: [
              { value: "by_version", label: "Por versión: cada puntaje dice qué versión se evaluó" },
              { value: "latest", label: "Versión vigente, marcando lo desactualizado" }
            ],
            hint: "Nunca se promedia entre versiones distintas sin decirlo." }
        ],
        advanced: [
          { key: "include_eliminated", type: "boolean", default: true,
            label: "Incluir las ideas que no avanzaron",
            hint: "El embudo siempre las cuenta; esto afecta al ranking y a la matriz." },
          { key: "step_slugs", type: "multi_select", source: "previous_steps",
            label: "Qué módulos abarca",
            hint: "Vacío = todos los anteriores a este." }
        ]
      }
    }.freeze

    class << self
      def for(kind) = SCHEMA.fetch(kind.to_s, { essential: [], advanced: [] })

      def fields(kind) = self.for(kind).values.flatten

      # Valores por defecto de un kind, para sembrar la config de un step nuevo.
      def defaults(kind)
        fields(kind).each_with_object({}) do |field, acc|
          next if field[:column] || !field.key?(:default)

          write(acc, field[:key], field[:default])
        end
      end

      # La config con la que el módulo REALMENTE corre: lo guardado sobre los
      # defaults del esquema.
      #
      # `config` sólo trae lo que alguien escribió, y las dos vías normales de
      # creación dejan huecos: `Flow::FlowTemplates` manda configs PARCIALES y
      # `db/seeds.rb` no manda ninguna —sólo `create_added` siembra
      # `defaults`—. Los handlers leen con `fetch(clave, default)`, así que un
      # hueco no significa "sin valor": significa el default. Mostrar el hueco
      # como ausencia era lo que dejaba la tarjeta de configuración congelada
      # ENTERA vacía en evolución y en reportería.
      def efectivo(kind, config)
        defaults(kind).deep_merge((config || {}).deep_stringify_keys)
      end

      # Un campo puede depender de otro: «Valor del corte» no describe nada con
      # la regla de corte en «manual». Espeja `visible` de `config_field.vue`,
      # contra el valor EFECTIVO —que ya trae el default del campo del que
      # depende, y por eso acá no hay que volver a buscarlo—.
      def visible?(campo, efectivo)
        regla = campo[:depends_on]
        return true if regla.nil?

        otro = read(efectivo, regla[:key])
        return otro != regla[:not] if regla.key?(:not)
        return otro == regla[:is] if regla.key?(:is)

        true
      end

      # La forma humana de un valor guardado, según lo que declara el campo.
      #
      # Sin esto la cara de ejecución mostraba el valor tal cual sale de
      # `config`: `false`, `trimmed_mean`, `by_version` o `["ideation",
      # "evaluation"]` con la sintaxis de `Array#inspect`. El `select` y el
      # `multi_select` ya traen `options` con su `label`; sólo hace falta
      # usarlas.
      #
      # No resuelve los campos `column: true` (p.ej. `source_step_id`): esos
      # no viven en `config` sino en una columna con su propia asociación, y
      # quien la tiene a mano es quien llama, no este método.
      def display_value(campo, valor)
        case campo[:type].to_s
        when "boolean"
          valor ? "Sí" : "No"
        when "select"
          etiqueta_de(campo, valor) || valor.to_s
        when "multi_select"
          Array(valor).map { |v| etiqueta_de(campo, v) || v.to_s }.join(", ")
        else
          valor.to_s
        end
      end

      # Lee una clave que puede ser anidada ("cut.mode").
      def read(config, key)
        key.to_s.split(".").reduce(config) do |node, segment|
          node.is_a?(Hash) ? node[segment] : nil
        end
      end

      def write(config, key, value)
        segments = key.to_s.split(".")
        last = segments.pop
        node = segments.reduce(config) { |acc, segment| acc[segment] ||= {} }
        node[last] = value
        config
      end

      # Filtra un `config` que llegó por parámetros contra lo que el esquema
      # declara para ese kind, y castea al tipo declarado.
      #
      # Dos motivos, los dos aprendidos a la mala:
      #
      #   · `params.permit(config: {})` es un escritor de jsonb arbitrario.
      #   · Un `cut.value` que llega `"4"` no explota —el handler hace `.to_f`—
      #     así que el string se arrastra hasta que alguien compara o serializa.
      #
      # Los campos `column: true` (source_step_id, criteria_set_id) NO son
      # config: viven en su columna y se permiten aparte. Valores malformados
      # —cuando la ruta no se puede recorrer o el tipo no es escalar— se
      # descartan sin error, sanando la entrada.
      #
      # OJO: esto también descarta claves que el esquema NO declara y que algún
      # handler SÍ lee. Hoy son las de `score_source` fuera de `combine`
      # (`Flow::Handlers::Selection`), y la lectura que importa es desde
      # `config`: `resolve_config!` saca `type`, `step_slugs` y `weights` de
      # `step.config` al arrancar para materializarlas —con `step_ids`— en
      # `resolved_config`, y `manual_source?` vuelve a mirar `type` en
      # `config`. Como `steps#update` reemplaza `config` entero por lo que
      # devuelve este método, una de esas claves puesta en `config` se
      # perdería en el siguiente guardado del módulo, antes de que nadie la
      # materialice. Con el módulo tocado ya no corren riesgo: viven en
      # `resolved_config`, que `filtrar` no toca, y `FROZEN_ATTRIBUTES` no deja
      # escribir `config`. Que hoy no sea un problema es un hecho de los
      # datos, no del mecanismo: en `config` no las pone nadie —ni las
      # plantillas, ni el seed, ni la base de desarrollo (0 filas)—, y la IA
      # tampoco puede: `Tasks::ProposePipeline#apply!` pasa por acá el
      # `config` que propone el modelo. Declararlas NO es agregar dos líneas:
      # `weights` es un mapa slug→peso y `filtrar` sólo sabe de escalares y de
      # arrays de `multi_select`, y `type` es una decisión de producto
      # (habilita «sin fuente de puntaje», que es lo que
      # `Flow::Pipeline#validate` mira para perdonar una selección sin
      # evaluación previa).
      def filtrar(kind, hash)
        # La raíz tiene que ser un Hash: un `config` que llega escalar
        # (`challenge_step[config]=x`) o en array (`challenge_step[config][]=x`)
        # no tiene `.to_h` seguro —revienta con `NoMethodError` o `TypeError`—
        # y la promesa de este método es sanar lo malformado, no reventar.
        entrada = hash.is_a?(Hash) ? hash.deep_stringify_keys : {}

        fields(kind).reject { |campo| campo[:column] }.each_with_object({}) do |campo, acc|
          clave = campo[:key].to_s
          valor = entrada.dig(*clave.split(".")) rescue nil
          next if valor.nil? || valor == ""
          next unless escalar_o_multi_select?(valor, campo[:type])

          write(acc, clave, castear(valor, campo[:type]))
        end
      end

      # El JSON Schema del `config` de un kind: lo que la IA puede proponer
      # (`Tasks::ProposePipeline`).
      #
      # Sale del mismo esquema que la UI, así que sumar una opción la suma acá
      # sin tocar la tarea. Deja afuera los campos `column:` —no son config— y
      # los de `source:`, que eligen otros módulos por id o por slug: al
      # proponer un flujo esos módulos todavía no existen.
      #
      # `minimum`/`maximum` quedan a propósito aunque el modelo no los vea: el
      # adapter de Anthropic los poda del pedido —la API los rechaza con 400—
      # y `SchemaValidator` los aplica igual sobre la respuesta. Por eso el
      # rango va también en la descripción, que es lo único que le llega.
      def json_schema(kind)
        campos = fields(kind).reject { |campo| campo[:column] || campo[:source] }

        campos.each_with_object({ "type" => "object", "properties" => {} }) do |campo, schema|
          *padres, hoja = campo[:key].to_s.split(".")
          nodo = padres.reduce(schema) do |acc, segmento|
            acc["properties"][segmento] ||= { "type" => "object", "properties" => {} }
          end
          nodo["properties"][hoja] = json_schema_de(campo, campos)
        end
      end

      def json_schema_de(campo, campos)
        schema =
          case campo[:type].to_s
          when "number" then { "type" => "number" }
          when "boolean" then { "type" => "boolean" }
          when "select" then { "type" => "string", "enum" => valores_de(campo) }
          when "multi_select" then { "type" => "array", "items" => { "type" => "string", "enum" => valores_de(campo) } }
          else raise ArgumentError, "el tipo de campo #{campo[:type].inspect} no tiene JSON Schema"
          end

        schema["minimum"] = campo[:min] if campo.key?(:min)
        schema["maximum"] = campo[:max] if campo.key?(:max)
        schema["default"] = campo[:default] if campo.key?(:default)
        schema.merge("description" => descripcion_de(campo, campos))
      end

      def valores_de(campo) = campo[:options].map { |opcion| opcion[:value].to_s }

      def descripcion_de(campo, campos)
        partes = [campo[:label], campo[:hint]]
        partes << opciones_de(campo) if campo[:options]
        partes << rango_de(campo) if campo.key?(:min) || campo.key?(:max)
        partes << condicion_de(campo[:depends_on], campos) if campo[:depends_on]
        partes.compact.map { |parte| "#{parte.to_s.chomp('.')}." }.join(" ")
      end

      # El `enum` le da al modelo los valores; lo que significa cada uno está
      # en la etiqueta que ve quien configura a mano.
      def opciones_de(campo)
        "Valores: " + campo[:options].map { |opcion| "`#{opcion[:value]}` (#{opcion[:label]})" }.join(", ")
      end

      def rango_de(campo)
        if campo.key?(:min) && campo.key?(:max) then "Un número entre #{campo[:min]} y #{campo[:max]}"
        elsif campo.key?(:min) then "Un número desde #{campo[:min]}"
        else "Un número hasta #{campo[:max]}"
        end
      end

      # Espeja `visible?`: «Valor del corte» no describe nada con la regla de
      # corte en «manual», y el modelo sólo se entera si se lo dicen.
      def condicion_de(regla, campos)
        otro = campos.find { |campo| campo[:key].to_s == regla[:key].to_s }
        return nil unless otro

        if regla.key?(:not)
          "Solo aplica cuando «#{otro[:label]}» no es «#{etiqueta_de(otro, regla[:not]) || regla[:not]}»"
        else
          "Solo aplica cuando «#{otro[:label]}» es «#{etiqueta_de(otro, regla[:is]) || regla[:is]}»"
        end
      end

      # El default del esquema es número: en `config_field.vue` el `v-else` es un
      # input numérico. Se espeja acá para que la UI y el server no discrepen.
      def castear(valor, tipo)
        case tipo.to_s
        when "select" then valor.to_s
        when "multi_select" then Array(valor).map(&:to_s)
        when "boolean" then ActiveModel::Type::Boolean.new.cast(valor).present?
        else valor.to_s.include?(".") ? valor.to_f : valor.to_i
        end
      end

      # Valida que el valor sea escalar o multi_select (que lo es Array).
      # Descarta valores malformados sin levantar.
      def escalar_o_multi_select?(valor, tipo)
        return true if valor.is_a?(String) || valor.is_a?(Numeric) || valor.is_a?(TrueClass) || valor.is_a?(FalseClass)
        return true if tipo.to_s == "multi_select" && valor.is_a?(Array)

        false
      end

      # Busca la `label` de un `value` dentro de las `options` del campo.
      # `nil` si el campo no declara opciones estáticas —los `source:`
      # dinámicos (`previous_evaluations`, `previous_steps`) las resuelven en
      # otro lado (`PipelinePresenter#settings_schema`) para la isla, y este
      # método no tiene ahí ningún desafío contra el que buscar.
      def etiqueta_de(campo, valor)
        campo[:options]&.find { |o| o[:value].to_s == valor.to_s }&.fetch(:label, nil)
      end

      private :castear, :escalar_o_multi_select?, :etiqueta_de,
              :json_schema_de, :valores_de, :descripcion_de, :opciones_de, :rango_de, :condicion_de
    end
  end
end
