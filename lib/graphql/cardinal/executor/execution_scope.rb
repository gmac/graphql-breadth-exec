# frozen_string_literal: true

module GraphQL::Cardinal
  class Executor
    class ExecutionScope
      attr_reader :parent_type, :selections, :sources, :responses, :parent

      def initialize(parent_type:, selections:, sources:, responses:, parent: nil)
        @parent_type = parent_type
        @selections = selections
        @sources = sources
        @responses = responses
        @parent = parent
      end
    end
  end
end
