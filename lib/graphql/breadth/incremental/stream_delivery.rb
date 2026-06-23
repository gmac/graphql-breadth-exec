# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    module Incremental
      class StreamDelivery
        #: error_path
        attr_reader :path

        #: String?
        attr_reader :label

        #: (error_path, ?String?) -> void
        def initialize(path, label = nil)
          @path = path.freeze
          @label = label
        end
      end
    end
  end
end
