# typed: true
# frozen_string_literal: true

module GraphQL
  module BreadthExec
    class Tracer
      #: (Executor, GraphQL::Query::Context) -> void
      def start(executor, context)
      end

      #: (Executor, GraphQL::Query::Context, duration: Float) -> void
      def finish(executor, context, duration:)
      end

      #: (Executor, GraphQL::Query::Context) -> void
      def before_execute(executor, context)
      end

      #: (Executor, GraphQL::Query::Context, duration: Float) -> void
      def after_execute(executor, context, duration:)
      end

      #: (Executor, GraphQL::Query::Context) -> void
      def before_format_errors(executor, context)
      end

      #: (Executor::AbstractExecutionScope, GraphQL::Query::Context) -> void
      def before_abstract_scope(abstract_scope, context)
      end

      #: (Executor::ExecutionScope, GraphQL::Query::Context) -> void
      def before_scope(exec_scope, context)
      end

      #: (Executor::ExecutionField[untyped], GraphQL::Query::Context) -> void
      def before_resolve_field(exec_field, context)
      end

      #: (Executor::ExecutionField[untyped], GraphQL::Query::Context, duration: Float) -> void
      def after_resolve_field(exec_field, context, duration:)
      end

      #: (LazyLoader[untyped], Array[Executor::LazyElement], GraphQL::Query::Context) -> void
      def before_lazy_set(loader, elements, context)
      end

      #: (LazyLoader[untyped], Array[Executor::LazyElement], GraphQL::Query::Context, duration: Float) -> void
      def after_lazy_set(loader, elements, context, duration:)
      end

      #: (Executor::ExecutionField[untyped], GraphQL::Query::Context) -> void
      def before_build_field_result(exec_field, context)
      end

      #: (Executor::ExecutionField[untyped], GraphQL::Query::Context, duration: Float) -> void
      def after_build_field_result(exec_field, context, duration:)
      end

      #: (Exception, GraphQL::Query::Context, ?exec_field: Executor::ExecutionField[untyped]?) -> void
      def on_exception(exception, context, exec_field: nil)
      end
    end
  end
end
