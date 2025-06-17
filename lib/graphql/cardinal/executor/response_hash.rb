# frozen_string_literal: true

module GraphQL::Cardinal
  class Executor
    class ResponseHash < Hash
      attr_accessor :typename
    end
  end
end
