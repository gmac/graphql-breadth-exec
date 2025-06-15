# frozen_string_literal: true

module GraphQL::Cardinal
  class BreadthExecutor
    class ExecutionScope
      attr_reader :parent_type, :selections, :sources, :responses

      def initialize(parent_type:, selections:, sources:, responses:)
        @parent_type = parent_type
        @selections = selections
        @sources = sources
        @responses = responses
      end
    end
  end
end
