# typed: true
# frozen_string_literal: true

module GraphQL::BreadthExec
  class Executor
    class ExecutionDirective
      include HasAttributes

      NOOP_DIRECTIVE_RESOLVER = NoopDirectiveResolver.new

      class << self
        #: (
        #|   executor: Executor,
        #|   node: GraphQL::Language::Nodes::Directive,
        #|   definition: singleton(GraphQL::Schema::Directive),
        #|   ?resolver: DirectiveResolver?,
        #|   ?depth: Integer,
        #| ) -> ExecutionDirective
        def build(executor:, node:, definition:, resolver: nil, depth: 0)
          new(
            executor: executor,
            name: node.name,
            node: node,
            definition: definition,
            resolver: resolver,
            depth: depth,
          )
        end
      end

      #: String
      attr_reader :name

      #: graphql_arguments
      attr_reader :arguments

      #: singleton(GraphQL::Schema::Directive)
      attr_reader :definition

      #: DirectiveResolver
      attr_reader :resolver

      #: GraphQL::Language::Nodes::Directive?
      attr_reader :node

      #: Integer
      attr_reader :depth

      #: (
      #|   executor: Executor,
      #|   name: String,
      #|   definition: singleton(GraphQL::Schema::Directive),
      #|   ?arguments: graphql_arguments?,
      #|   ?node: GraphQL::Language::Nodes::Directive?,
      #|   ?resolver: DirectiveResolver?,
      #|   ?depth: Integer,
      #| ) -> void
      def initialize(executor:, name:, definition:, arguments: nil, node: nil, resolver: nil, depth: 0)
        @name = name
        @node = node
        @definition = definition
        @resolver = resolver || NOOP_DIRECTIVE_RESOLVER
        @depth = depth
        @arguments, @argument_errors = if arguments.nil?
          executor.input.coerce_argument_values(@definition, @node)
        else
          [arguments, EMPTY_ARRAY]
        end
        @mutable_arguments = nil
      end

      #: () -> String
      def inspect
        "#<ExecutionDirective: @#{name}>"
      end

      #: () -> graphql_arguments
      def mutable_arguments
        @mutable_arguments ||= Util.deep_copy(@arguments)
      end

      #: () -> void
      def validate!
        unless @argument_errors.empty?
          @argument_errors.each { _1.add_parent_node(@node) } if @node
          raise InputValidationErrorSet.new(errors: @argument_errors)
        end
      end
    end
  end
end
