# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    class ListStreamChunk
      #: Array[untyped]
      attr_reader :items

      #: (items: Array[untyped], complete: bool) -> void
      def initialize(items:, complete:)
        @items = items
        @complete = complete
      end

      #: -> bool
      def complete?
        @complete
      end
    end
  end
end
