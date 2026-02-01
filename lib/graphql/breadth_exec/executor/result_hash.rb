# frozen_string_literal: true

module GraphQL::BreadthExec
  class Executor
    class ResultHash < Hash
      attr_accessor :typename
    end
  end
end
