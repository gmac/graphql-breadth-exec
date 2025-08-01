# frozen_string_literal: true

module GraphQL::Cardinal
  class Executor
    class ExecutionField
      attr_reader :key, :node
      attr_accessor :scope, :type, :result

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

      def arguments(vars)
        return EMPTY_OBJECT if @node.arguments.empty?

        @arguments ||= @node.arguments.each_with_object({}) do |arg, args|
          args[arg.name] = build_arguments(arg.value, vars)
        end
      end

      private

      def build_arguments(value, vars)
        case value
        when GraphQL::Language::Nodes::VariableIdentifier
          vars[value.name] || vars[value.name.to_sym]
        when GraphQL::Language::Nodes::NullValue
          nil
        when GraphQL::Language::Nodes::InputObject
          value.arguments.each_with_object({}) do |arg, obj|
            obj[arg.name] = build_arguments(arg.value, vars)
          end
        when Array
          value.map { |item| build_arguments(item, vars) }
        else
          value
        end
      end
    end
  end
end
