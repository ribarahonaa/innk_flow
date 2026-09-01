# frozen_string_literal: true

module Flow
  module Formula
    # Seis chequeos ESTÁTICOS sobre la expresión de un criterio. Todos antes de
    # ejecutar nada, y ninguno usa eval.
    class Validator
      def initialize(criterion)
        @criterion = criterion
      end

      attr_reader :criterion

      def valid? = errors.empty?

      def errors
        @errors ||= run_checks
      end

      private

      def expression = criterion.scale_config.to_h["expression"].to_s

      def run_checks
        return ["la fórmula está vacía"] if expression.blank?

        # 1. Límites duros PRIMERO: una expresión patológica no debería ni
        #    llegar al parser.
        return ["la fórmula no puede superar #{Calculator::MAX_LENGTH} caracteres"] if expression.length > Calculator::MAX_LENGTH

        calculator = Calculator.new(expression)

        # 2. Parse
        begin
          calculator.ast
        rescue Dentaku::ParseError, Dentaku::TokenizerError, StandardError => e
          return ["no se pudo interpretar la fórmula: #{e.message}"]
        end

        errors = []

        # 3. Profundidad
        errors << "la fórmula es demasiado compleja (anidamiento > #{Calculator::MAX_DEPTH})" if calculator.depth > Calculator::MAX_DEPTH

        # 4. Referencias: cada variable tiene que ser el `key` de otro criterio
        #    ACTIVO del mismo set.
        dependencies = calculator.dependencies
        errors << "la fórmula referencia demasiados criterios (#{dependencies.size})" if dependencies.size > Calculator::MAX_DEPENDENCIES

        unknown = dependencies - sibling_keys
        unknown.each do |name|
          errors << "la fórmula referencia «#{name}», que no es un criterio de este set"
        end

        errors << "la fórmula no puede referenciarse a sí misma" if dependencies.include?(criterion.key.to_s)

        # 5. Whitelist de funciones
        forbidden = calculator.functions_used - Calculator::ALLOWED_FUNCTIONS
        forbidden.each do |name|
          errors << "la función «#{name}» no está permitida"
        end

        # 6. Ciclos entre criterios fórmula
        if errors.empty? && (path = cycle_path)
          errors << "hay un ciclo entre criterios: #{path.join(' → ')}"
        end

        errors
      end

      def siblings
        @siblings ||= begin
          set = criterion.criteria_set
          return [] if set.nil?

          set.criteria.select(&:active).reject { |c| c.id.present? && c.id == criterion.id }
        end
      end

      def sibling_keys = siblings.map(&:key).map(&:to_s)

      # DFS sobre el grafo de dependencias del set. Devuelve el camino del
      # ciclo para que el mensaje sea accionable.
      def cycle_path
        graph = siblings.each_with_object({}) do |sibling, acc|
          acc[sibling.key.to_s] = formula_dependencies(sibling)
        end
        graph[criterion.key.to_s] = Calculator.new(expression).dependencies

        visit(criterion.key.to_s, graph, [], {})
      end

      def formula_dependencies(sibling)
        return [] unless sibling.source == "formula"

        Calculator.new(sibling.scale_config.to_h["expression"]).dependencies
      rescue StandardError
        []
      end

      def visit(node, graph, path, state)
        return path + [node] if state[node] == :visiting
        return nil if state[node] == :done

        state[node] = :visiting
        Array(graph[node]).each do |child|
          found = visit(child, graph, path + [node], state)
          return found if found
        end
        state[node] = :done
        nil
      end
    end
  end
end
