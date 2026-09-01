# frozen_string_literal: true

module Flow
  module Formula
    # Evaluación de expresiones con dentaku. NUNCA eval.
    #
    # Dentaku es Ruby puro con tokenizer/parser/evaluator propios: la expresión
    # se convierte en un AST y se recorre, no se ejecuta como código. No hay
    # eval, instance_eval ni send en el camino, y la expresión nunca toca un
    # objeto Ruby.
    #
    # El calculador se construye SIN add_function: si una función no está
    # registrada, no existe. La whitelist es por construcción, no por filtro.
    class Calculator
      # Solo lo que el dueño de un desafío necesita para combinar criterios.
      ALLOWED_FUNCTIONS = %w[if min max round roundup rounddown abs and or not].freeze

      MAX_LENGTH = 500
      MAX_DEPTH = 20
      MAX_DEPENDENCIES = 25

      def initialize(expression)
        @expression = expression.to_s
      end

      attr_reader :expression

      def ast
        @ast ||= calculator.ast(expression)
      end

      # Identificadores que la expresión referencia. Es la primitiva que
      # permite validar las referencias SIN ejecutar nada.
      def dependencies
        calculator.dependencies(expression).map(&:to_s)
      end

      # Funciones usadas, recorriendo el AST. Doble red junto al calculador
      # sin funciones registradas: si una versión futura de la gema trae
      # builtins nuevos, este walk igual los caza.
      def functions_used
        collect_functions(ast)
      end

      def depth = node_depth(ast)

      def evaluate(bindings)
        values = bindings.transform_keys(&:to_s).transform_values { |v| v.nil? ? nil : v.to_f }
        return nil if values.values.any?(&:nil?)

        # evaluate!(expr, data) y no solve!: solve! resuelve un HASH de
        # expresiones, evaluate! resuelve UNA con sus variables.
        result = calculator.evaluate!(expression, values)
        result.nil? ? nil : result.to_d
      rescue Dentaku::UnboundVariableError, Dentaku::ZeroDivisionError,
             Dentaku::ArgumentError, Dentaku::ParseError, ::ArgumentError, TypeError => e
        raise Flow::Errors::InvalidFormula, e.message
      end

      private

      # Sin add_function: la whitelist es lo que la gema trae de fábrica y
      # nada más.
      def calculator = @calculator ||= Dentaku::Calculator.new

      def collect_functions(node, found = [])
        klass = node.class.name.to_s
        if node.is_a?(Dentaku::AST::Function) || klass.start_with?("Dentaku::AST::")
          name = node.class.name.demodulize.downcase
          found << name if node.is_a?(Dentaku::AST::Function)
        end

        children_of(node).each { |child| collect_functions(child, found) }
        found.uniq
      end

      def node_depth(node)
        children = children_of(node)
        return 1 if children.empty?

        1 + children.map { |child| node_depth(child) }.max
      end

      def children_of(node)
        %i[left right @args].filter_map do |accessor|
          if accessor == :@args
            node.instance_variable_get(:@args) if node.instance_variable_defined?(:@args)
          elsif node.respond_to?(accessor)
            node.public_send(accessor)
          end
        end.flatten.compact
      end
    end
  end
end
