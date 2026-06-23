# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    module Incremental
      class DeferredDelivery < Delivery
        #: DeferredDelivery?
        attr_reader :parent

        #: (error_path, ?String?, ?parent: DeferredDelivery?) -> void
        def initialize(path, label = nil, parent: nil)
          super(path, label)
          @parent = parent
        end
      end
    end
  end
end
