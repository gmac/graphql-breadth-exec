# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    module Incremental
      class DeferUsage
        #: String?
        attr_reader :label

        #: DeferUsage?
        attr_reader :parent

        #: (?String?, ?parent: DeferUsage?) -> void
        def initialize(label = nil, parent: nil)
          @label = label
          @parent = parent
        end
      end
    end
  end
end
