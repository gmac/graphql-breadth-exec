# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    class Executor
      class AbstractExecutionScope
        #: singleton(GraphQL::Schema::Member)
        attr_reader :parent_type

        #: ExecutionField[untyped]
        attr_reader :parent_field

        #: Array[ExecutionScope]
        attr_reader :scopes

        #: (
        #|   parent_type: singleton(GraphQL::Schema::Member),
        #|   parent_field: ExecutionField[untyped],
        #|   scopes: Array[ExecutionScope],
        #| ) -> void
        def initialize(parent_type:, parent_field:, scopes:)
          @parent_type = parent_type
          @parent_field = parent_field
          @scopes = scopes
          @executed = false
        end

        #: -> bool
        def executed?
          @executed
        end

        #: -> Executor
        def executor
          @parent_field.executor
        end

        #: -> ExecutionScope
        def parent
          @parent_field.scope
        end

        #: -> Array[String]
        def path
          @parent_field.path
        end

        #: -> Integer
        def depth
          @parent_field.depth
        end

        #: -> Array[untyped]
        def objects
          @objects ||= @scopes.flat_map(&:objects)
        end

        #: -> Array[untyped]
        def results
          @results ||= @scopes.flat_map(&:results)
        end
      end
    end
  end
end
