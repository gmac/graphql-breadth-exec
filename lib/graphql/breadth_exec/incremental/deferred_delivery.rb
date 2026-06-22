# typed: true
# frozen_string_literal: true

module GraphQL
  module BreadthExec
    module Incremental
      class DeferredDelivery
        #: error_path
        attr_reader :path

        #: String?
        attr_reader :label

        #: DeferredDelivery?
        attr_reader :parent

        #: (error_path, ?String?, ?parent: DeferredDelivery?) -> void
        def initialize(path, label = nil, parent: nil)
          @path = path.freeze
          @label = label
          @parent = parent
        end

        # True when this delivery's path is a prefix of (or equal to) `path`,
        # i.e. `path` falls at or below this delivery in the result tree.
        #: (error_path) -> bool
        def path_prefix_of?(path)
          return false if @path.length > path.length

          i = 0
          while i < @path.length
            return false unless @path[i] == path[i]

            i += 1
          end

          true
        end
      end
    end
  end
end
