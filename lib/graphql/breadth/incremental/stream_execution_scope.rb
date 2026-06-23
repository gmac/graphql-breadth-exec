# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    module Incremental
      class StreamExecutionScope < Executor::ExecutionScope
        #: StreamDelivery
        attr_reader :delivery

        #: Array[untyped]
        attr_reader :items

        #: Integer
        attr_reader :initial_index

        #: bool
        attr_writer :announced

        #: (
        #|   parent_field: Executor::ExecutionField[untyped],
        #|   parent_type: singleton(GraphQL::Schema::Object),
        #|   selections: Array[selection_node],
        #|   objects: Array[untyped],
        #|   results: Array[untyped],
        #|   items: Array[untyped],
        #|   object_paths: Array[error_path],
        #|   delivery: StreamDelivery,
        #|   initial_index: Integer,
        #| ) -> void
        def initialize(parent_field:, parent_type:, selections:, objects:, results:, items:, object_paths:, delivery:, initial_index:)
          @delivery = delivery
          @items = items
          @object_paths = object_paths
          @initial_index = initial_index
          @announced = false

          super(
            executor: parent_field.executor,
            parent_type:,
            selections:,
            objects:,
            results:,
            parent_field:,
            deferred: true,
          )
        end

        #: -> bool
        def ready?
          field = parent_field #: as !nil
          field.scope.executed? && !field.scope.aborted?
        end

        #: -> bool
        def announced?
          @announced
        end

        #: -> StreamExecutionScope
        def prepare!
          self
        end

        #: (Integer) -> error_path
        def item_path(index)
          [*@delivery.path, @initial_index + index]
        end

        #: (Integer) -> error_path
        def stream_item_path(index)
          @object_paths[index] || item_path(index)
        end

        #: (Integer) -> error_path
        def object_path(index)
          stream_item_path(index)
        end
      end
    end
  end
end
