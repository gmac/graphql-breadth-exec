# frozen_string_literal: true

module GraphQL::Cardinal
  class Executor
    class ExecutionField
      attr_reader :key, :node, :arguments
      attr_accessor :scope, :field, :type, :result

      def initialize(key, scope = nil)
        @key = key.freeze
        @scope = scope
        @name = nil
        @node = nil
        @nodes = nil
        @type = nil
        @result = nil
        @arguments = nil
        @path = nil
      end

      def name
        @name ||= @node.name.freeze
      end

      def path
        @path ||= (@scope ? [*@scope.path, @key] : []).freeze
      end

      def add_node(n)
        if !@node
          @node = n
        elsif !@nodes
          @nodes = [@node, n]
        else
          @nodes << n
        end
      end

      def nodes
        @nodes ? @nodes : [@node]
      end

      def selections
        if @nodes
          @nodes.flat_map(&:selections)
        else
          @node.selections
        end
      end

      def build_arguments(query, vars)
        raise "Cannot rebuild arguments" unless @arguments.nil?

        @arguments = if !@node.arguments.empty?
          base_args = build_default_arguments(query, field)

          @node.arguments.each_with_object({}) do |n, args|
            arg_def = query.types.argument(field, n.name)
            args[n.name] = build_argument(n.value, query, arg_def, vars)
          end
        else
          EMPTY_OBJECT
        end
        pp @arguments

        @arguments
      end

      private

      def build_default_arguments(query, owner)
        query.types.arguments(owner).each_with_object({}) do |arg, memo|
          next unless arg.default_value?

          binding.pry
          memo[arg.name] = arg.default_value
        end
      end

      def build_argument(value, query, arg_def, vars)
        case value
        when GraphQL::Language::Nodes::VariableIdentifier
          vars[value.name] || vars[value.name.to_sym]
        when GraphQL::Language::Nodes::NullValue
          nil
        when GraphQL::Language::Nodes::InputObject
          input_type = arg_def.type.unwrap
          base_args = query.types.arguments(input_type).each_with_object({}) do |arg, memo|
            memo[arg.name] = arg.default_value if arg.default_value?
          end

          value.arguments.each_with_object(base_args) do |n, obj|
            arg_def = query.types.argument(input_type, n.name)
            obj[n.name] = build_argument(n.value, query, arg_def, vars)
          end
        when Array
          value.map { build_argument(_1, query, arg_def, vars) }
        else
          value
        end
      end
    end
  end
end
