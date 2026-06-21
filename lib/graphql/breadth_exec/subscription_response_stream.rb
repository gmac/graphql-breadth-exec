# typed: true
# frozen_string_literal: true

module GraphQL
  module BreadthExec
    class SubscriptionResponseStream
      include Enumerable

      #: Executor
      attr_reader :executor

      #: Enumerable
      attr_reader :source_stream

      #: (executor: Executor, source_stream: Enumerable) -> void
      def initialize(executor:, source_stream:)
        @executor = executor
        @source_stream = source_stream
      end

      #: () ?{ (graphql_result) -> void } -> Enumerator?
      def each(&block)
        return enum_for(:each) unless block

        @source_stream.each do |source_event|
          block.call(@executor.execute_subscription_event(source_event))
        end

        nil
      end
    end
  end
end
