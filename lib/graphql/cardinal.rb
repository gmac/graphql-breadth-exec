# frozen_string_literal: true

require "graphql"

module GraphQL
  # In honor of cardinality, Bluejay, and my office mate
  # who attacks his own reflection in my window all summer...
  module Cardinal
    EMPTY_OBJECT = {}.freeze

    class ExecutionError < StandardError; end
    class InternalError < ExecutionError; end
    class InvalidNullError < ExecutionError; end
    class AuthorizationError < ExecutionError; end
    class DocumentError < StandardError; end
  end
end

require_relative "cardinal/promise"
require_relative "cardinal/scalars"
require_relative "cardinal/shaper"
require_relative "cardinal/breadth_executor"
require_relative "cardinal/depth_executor"
require_relative "cardinal/version"
