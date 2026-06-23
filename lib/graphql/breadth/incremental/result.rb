# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    module Incremental
      class Result
        #: graphql_result
        attr_reader :initial_result

        #: Enumerable
        attr_reader :subsequent_results

        #: (initial_result: graphql_result, subsequent_results: Enumerable) -> void
        def initialize(initial_result:, subsequent_results:)
          @initial_result = initial_result
          @subsequent_results = subsequent_results
          @incremental = subsequent_results != EMPTY_ARRAY
        end

        #: -> bool
        def incremental?
          @incremental
        end

        #: -> graphql_result
        def to_h
          return @initial_result unless incremental?

          {
            "initialResult" => @initial_result,
            "subsequentResults" => @subsequent_results.to_a,
          }
        end
      end
    end
  end
end
