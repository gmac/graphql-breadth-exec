# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    module Incremental
      class ListStreamEntry
        #: untyped
        attr_reader :object

        #: Hash[untyped, untyped]
        attr_reader :object_state

        #: StreamExecutionScope?
        attr_accessor :scope

        #: Executor::ListStreamField
        attr_writer :field

        #: (object: untyped, object_state: Hash[untyped, untyped]) -> void
        def initialize(object:, object_state:)
          @object = object
          @object_state = object_state
          @scope = nil
          @field = nil #: Executor::ListStreamField?
        end

        #: -> Executor::ListStreamField
        def field
          @field || raise(ImplementationError, "List stream entry has no field")
        end
      end

      class ListStreamSource
        #: Array[untyped]
        attr_reader :initial_items

        #: untyped
        attr_reader :remaining_items

        #: (initial_items: Array[untyped], remaining_items: untyped) -> void
        def initialize(initial_items:, remaining_items:)
          @initial_items = initial_items
          @remaining_items = remaining_items
        end
      end
    end
  end
end
