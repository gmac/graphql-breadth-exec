# typed: true
# frozen_string_literal: true

module GraphQL
  module BreadthExec
    class DirectiveResolver
      #: (?wraps: bool, ?cascades: bool) -> void
      def initialize(wraps: false, cascades: false)
        @wraps = wraps
        @cascades = cascades
      end

      #: () -> bool
      def wraps?
        @wraps
      end

      #: () -> bool
      def cascades?
        @cascades
      end

      #: (Executor::ExecutionDirective, Executor::ExecutionField[untyped]?) -> bool
      def applies?(exec_directive, exec_field)
        return true if exec_field.nil? || cascades?

        exec_directive.depth == exec_field.depth
      end

      #: (
      #|   Executor::ExecutionDirective,
      #|   GraphQL::Query::Context,
      #|   ?current_field: Executor::ExecutionField[untyped]?,
      #| ) ?{ () -> untyped } -> untyped
      def resolve(_exec_directive, _context, current_field: nil, &block)
        raise MethodNotImplementedError, "DirectiveResolver#resolve must be implemented."
      end
    end

    class NoopDirectiveResolver < DirectiveResolver
      #: (
      #|   Executor::ExecutionDirective,
      #|   GraphQL::Query::Context,
      #|   ?current_field: Executor::ExecutionField[untyped]?,
      #| ) ?{ () -> untyped } -> untyped
      def resolve(_exec_directive, _context, current_field: nil, &block)
        nil
      end
    end
  end
end
