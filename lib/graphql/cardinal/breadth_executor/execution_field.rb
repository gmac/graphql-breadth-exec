# frozen_string_literal: true

module GraphQL::Cardinal
  class BreadthExecutor
    class ExecutionField
      attr_reader :node, :nodes

      def initialize
        @node = nil
        @nodes = nil
        @arguments = nil
      end

      def name
        @node.name
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

      def selections
        if @nodes
          @nodes.flat_map(&:selections)
        else
          @node.selections
        end
      end

      def arguments(vars)
        return EMPTY_OBJECT if @node.arguments.empty?

        @arguments ||= @node.arguments.each_with_object({}) do |arg, args|
          args[arg.name] = coerce_arguments(arg.value, vars)
        end
      end

      private

      def coerce_arguments(value, vars)
        case value
        when GraphQL::Language::Nodes::VariableIdentifier
          vars[value.name] || vars[value.name.to_sym]
        when GraphQL::Language::Nodes::NullValue
          nil
        when GraphQL::Language::Nodes::InputObject
          value.arguments.each_with_object({}) do |arg, obj|
            obj[arg.name] = coerce_arguments(arg.value, vars)
          end
        when Array
          value.map { |item| coerce_arguments(item, vars) }
        else
          value
        end
      end
    end
  end
end
