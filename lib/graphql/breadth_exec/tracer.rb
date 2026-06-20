# typed: true
# frozen_string_literal: true

module GraphQL
  module BreadthExec
    class Tracer
      #: (Executor, GraphQL::Query::Context) -> void
      def start(*)
      end

      #: (Executor, GraphQL::Query::Context, duration: Float) -> void
      def finish(*, duration:)
      end

      #: (Executor, GraphQL::Query::Context) -> void
      def before_execute(*)
      end

      #: (Executor, GraphQL::Query::Context, duration: Float) -> void
      def after_execute(*, duration:)
      end

      #: (Executor, GraphQL::Query::Context) -> void
      def before_format_errors(*)
      end

      #: (singleton(GraphQL::Schema::Member), String, Integer, GraphQL::Query::Context) -> void
      def before_resolve_field(*)
      end

      #: (singleton(GraphQL::Schema::Member), String, Integer, GraphQL::Query::Context, ?duration: Float?) -> Float?
      def after_resolve_field(*args, duration: nil)
      end

      #: (Executor::ExecutionField[untyped], GraphQL::Query::Context) -> void
      def before_build_field_result(*)
      end

      #: (Executor::ExecutionField[untyped], GraphQL::Query::Context, duration: Float) -> void
      def after_build_field_result(*, duration:)
      end

      #: (Exception, GraphQL::Query::Context, ?exec_field: Executor::ExecutionField[untyped]?) -> void
      def on_exception(*, exec_field: nil)
      end
    end
  end
end
