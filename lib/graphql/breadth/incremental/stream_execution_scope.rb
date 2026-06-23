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

        #: Array[error_path]
        attr_reader :object_paths

        #: Integer
        attr_reader :initial_index

        #: bool
        attr_writer :announced

        #: bool
        attr_reader :prepared

        #: ListStreamEntry?
        attr_reader :list_stream_entry

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
        #|   ?prepare: Proc?,
        #|   ?list_stream_entry: ListStreamEntry?,
        #| ) -> void
        def initialize(parent_field:, parent_type:, selections:, objects:, results:, items:, object_paths:, delivery:, initial_index:, prepare: nil, list_stream_entry: nil)
          @delivery = delivery
          @items = items
          @object_paths = object_paths
          @initial_index = initial_index
          @next_index = initial_index
          @prepare = prepare
          @list_stream_entry = list_stream_entry
          @prepared = false
          @complete = false
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
          !complete? && field.scope.executed? && !field.scope.aborted?
        end

        #: -> bool
        def announced?
          @announced
        end

        #: -> bool
        def stream?
          !!@list_stream_entry
        end

        #: -> bool
        def complete?
          @complete
        end

        #: -> void
        def complete!
          @complete = true
        end

        #: -> StreamExecutionScope
        def prepare!
          unless @prepared
            @prepare&.call(self)
            @prepared = true
            @complete = true unless stream?
          end

          self
        end

        #: (Array[untyped]) -> StreamExecutionScope
        def prepare_list_stream_items!(raw_items)
          reset_installment!
          @prepare&.call(self, raw_items)
          @prepared = true
          self
        end

        #: -> void
        def finish_installment!
          @next_index = @initial_index + @items.length
          @prepared = false
          self.executed = false unless complete?
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

        private

        #: -> void
        def reset_installment!
          @initial_index = @next_index
          @items = []
          @objects = []
          @results = []
          @object_paths = []
          @fields = {}
          @sync_preloads = nil
          @lazy_preloads = nil
          @preload_promises = nil
          @lazy_state = LAZY_STATE_PRELOADING
        end
      end
    end
  end
end
