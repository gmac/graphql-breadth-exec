# typed: true
# frozen_string_literal: true

module GraphQL::BreadthExec
  class Executor
    class ExecutionScope
      include LazyElement
      include HasAttributes

      #: Executor
      attr_reader :executor

      #: singleton(GraphQL::Schema::Object)
      attr_reader :parent_type

      #: ExecutionField[untyped]?
      attr_reader :parent_field

      #: Array[selection_node]
      attr_reader :selections

      #: Array[untyped]
      attr_reader :objects

      #: Array[untyped]
      attr_reader :results

      #: AbstractExecutionScope?
      attr_reader :abstraction

      #: Array[String]
      attr_reader :path

      #: ExecutionScope?
      attr_reader :parent

      #: Hash[String, ExecutionField[untyped]]
      attr_accessor :fields

      #: bool
      attr_writer :executed

      #: (
      #|   executor: Executor,
      #|   parent_type: singleton(GraphQL::Schema::Object),
      #|   selections: Array[selection_node],
      #|   objects: Array[untyped],
      #|   results: Array[untyped],
      #|   ?abstraction: AbstractExecutionScope?,
      #|   ?parent_field: ExecutionField[untyped]?,
      #|   ?path: Array[String],
      #|   ?parent: ExecutionScope?,
      #| ) -> void
      def initialize(
        executor:,
        parent_type:,
        selections:,
        objects:,
        results:,
        abstraction: nil,
        parent_field: nil,
        path: [],
        parent: nil
      )
        super()
        @executor = executor
        @parent_type = parent_type
        @parent_field = parent_field
        @selections = selections
        @objects = objects
        @results = results
        @abstraction = abstraction
        @path = (parent_field ? parent_field.path : path).freeze
        @parent = parent_field ? parent_field.scope : parent
        @fields = nil
        @executed = false
        @root = nil
        @planning_root = nil
        @aborted = false
      end

      #: -> GraphQL::Query::Context
      def context
        @executor.context
      end

      #: -> ExecutionScope
      def root
        @root ||= begin
          next_scope = Util.deep_copy(self)
          next_scope = next_scope.parent while next_scope.parent
          next_scope
        end
      end

      #: -> ExecutionScope
      def planning_root
        @planning_root ||= begin
          next_scope = Util.deep_copy(self)
          while next_scope.parent
            return next_scope if next_scope.abstraction

            next_scope = next_scope.parent
          end
          next_scope
        end
      end

      #: -> Integer
      def depth
        @path.length
      end

      #: -> Array[String]
      def schema_path
        parent_field ? parent_field.schema_path : EMPTY_ARRAY
      end

      #: (Integer) -> error_path
      def object_path(index)
        @executor.paths.object_path(self, index)
      end

      #: -> bool
      def executed?
        @executed
      end

      #: -> bool
      def abort!
        @aborted = true
      end

      #: -> bool
      def aborted?
        @aborted
      end

      #: -> bool
      def aborted_subtree?
        return true if @aborted

        exec_field = parent_field
        while exec_field
          if exec_field.scope.aborted?
            abort!
            return true
          end
          exec_field = exec_field.scope.parent_field
        end
        false
      end

      #: -> bool
      def has_authorized_objects?
        @objects.frozen? && !@objects.empty?
      end

      #: -> String
      def inspect
        "#<ExecutionScope: [#{path.join(", ")}]>"
      end
    end
  end
end
