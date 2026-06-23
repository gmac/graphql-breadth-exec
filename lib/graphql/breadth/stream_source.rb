# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    class StreamSource
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
