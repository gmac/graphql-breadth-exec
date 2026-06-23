# typed: true
# frozen_string_literal: true

module GraphQL
  module BreadthExec
    module Incremental
      class Selection
        #: GraphQL::Language::Nodes::Field
        attr_reader :node

        #: DeferUsage?
        attr_reader :defer_usage

        #: (GraphQL::Language::Nodes::Field, ?defer_usage: DeferUsage?) -> void
        def initialize(node, defer_usage: nil)
          @node = node
          @defer_usage = defer_usage
        end
      end
    end
  end
end
