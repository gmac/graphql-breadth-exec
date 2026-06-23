# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    class Executor
      class ListStreamField
        include LazyElement
        include HasAttributes

        LAZY_STATE_EXECUTING = :executing

        #: ExecutionField[untyped]
        attr_reader :parent_field

        #: Array[Incremental::ListStreamEntry]
        attr_reader :pending_entries

        #: Hash[untyped, untyped]
        attr_reader :state

        #: Integer?
        attr_reader :limit

        #: Integer
        attr_accessor :iteration

        #: untyped
        attr_accessor :result

        #: (
        #|   parent_field: ExecutionField[untyped],
        #|   pending_entries: Array[Incremental::ListStreamEntry],
        #|   state: Hash[untyped, untyped],
        #|   limit: Integer?,
        #| ) -> void
        def initialize(parent_field:, pending_entries:, state:, limit:)
          super()
          @parent_field = parent_field
          @pending_entries = pending_entries
          @state = state
          @limit = limit
          @iteration = 0
          @result = nil
        end

        #: -> Array[untyped]
        def objects
          @pending_entries.map(&:object)
        end

        #: -> Array[Hash[untyped, untyped]]
        def object_states
          @pending_entries.map(&:object_state)
        end

        #: -> Executor
        def executor
          @parent_field.executor
        end

        #: -> GraphQL::Query::Context
        def context
          @parent_field.context
        end

        #: -> FieldResolver
        def resolver
          @parent_field.resolver
        end

        #: -> graphql_arguments
        def arguments
          @parent_field.arguments
        end

        #: -> graphql_arguments
        def mutable_arguments
          @parent_field.mutable_arguments
        end

        #: -> singleton(GraphQL::Schema::Member)
        def type
          @parent_field.type
        end

        #: -> Array[GraphQL::Language::Nodes::Field]
        def nodes
          @parent_field.nodes
        end

        #: -> Array[selection_node]
        def selections
          @parent_field.selections
        end

        #: -> String
        def key
          @parent_field.key
        end

        #: -> String
        def name
          @parent_field.name
        end

        #: -> Array[String]
        def path
          @parent_field.path
        end

        #: (
        #|   loader_class: singleton(LazyLoader),
        #|   keys: Array[untyped],
        #|   ?args: loader_args?,
        #|   ?eager_values: Hash[untyped, untyped]?,
        #|   ?load_nil_keys: bool,
        #| ) -> ExecutionPromise
        def lazy(loader_class:, keys:, args: nil, eager_values: nil, load_nil_keys: false)
          unless allows_lazy?
            raise LazySequencingError.new(lazy_element: self, method_name: "lazy")
          end

          executor.lazy_loader_for(loader_class, args).load(
            element: self,
            keys: keys,
            eager_values: eager_values,
            load_nil_keys: load_nil_keys,
          )
        end

        #: (Array[ExecutionPromise]) -> ExecutionPromise
        def await_all(promises)
          super
        end

        #: -> bool
        def allows_lazy?
          @lazy_state == LAZY_STATE_EXECUTING
        end

        #: [T] (T) -> Array[T]
        def resolve_all(value)
          value = case value
          when StandardError
            handle_or_reraise(value)
          else
            value
          end
          Array.new(objects.length, value)
        end

        #: (limit: Integer?) -> void
        def reset_for_resolve!(limit:)
          @limit = limit
          @result = nil
          @sync_preloads = nil
          @lazy_preloads = nil
          @preload_promises = nil
          @lazy_state = LAZY_STATE_PRELOADING
        end

        #: (Array[Incremental::ListStreamEntry]) -> void
        def drop_pending_entries(entries)
          @pending_entries -= entries
        end

        #: (Array[Incremental::ListStreamEntry]) -> void
        def retain_pending_entries(entries)
          @pending_entries &= entries
        end

        #: (Exception) -> ExecutionError
        def handle_or_reraise(error)
          executor.handle_or_reraise(error, exec_field: @parent_field)
        end

        #: () -> bool
        def lazy_result?
          @result.is_a?(ExecutionPromise)
        end

        #: () -> bool
        def has_result?
          !@result.nil?
        end

        #: () -> bool
        def locked?
          @lazy_state == LAZY_STATE_LOCKED
        end

        #: () -> String
        def inspect
          "#<ListStreamField: #{@parent_field.inspect}>"
        end

        #: () -> void
        def lazy_state_executing!
          raise LazyStateTransitionError.new(@lazy_state, LAZY_STATE_EXECUTING) unless @lazy_state == LAZY_STATE_PRELOADING

          @lazy_state = LAZY_STATE_EXECUTING
        end

        private

        #: () -> bool
        def lazy_state_lockable?
          @lazy_state == LAZY_STATE_PRELOADING || @lazy_state == LAZY_STATE_EXECUTING
        end
      end
    end
  end
end
