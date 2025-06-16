# frozen_string_literal: true

module GraphQL::Cardinal
  class BreadthExecutor
    class ExecutionField
      attr_reader :node, :nodes

      def initialize
        @node = nil
        @nodes = nil
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

        @node.arguments.each_with_object({})do |a, args|
          args[a.name] = a.value
        end
      end
    end
  end
end
