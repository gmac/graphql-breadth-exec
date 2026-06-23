# typed: true
# frozen_string_literal: true

require "graphql"

module GraphQL
  module Breadth
    class Authorization
      #: (Executor::ExecutionField[untyped], GraphQL::Query::Context) -> bool
      def authorized_field?(exec_field, context)
        true
      end

      #: (singleton(GraphQL::Schema::Member), GraphQL::Query::Context, ?exec_field: Executor::ExecutionField[untyped]?) -> bool
      def authorized_type?(type, context, exec_field: nil)
        true
      end

      #: (Executor::ExecutionScope, GraphQL::Query::Context) -> bool
      def authorize_objects_in_scope?(exec_scope, context)
        false
      end

      #: (Executor::ExecutionScope, GraphQL::Query::Context) -> invalidated_indices
      def unauthorized_object_indices(exec_scope, context)
        EMPTY_OBJECT
      end
    end
  end
end
