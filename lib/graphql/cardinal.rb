# frozen_string_literal: true

require "graphql"

module GraphQL
  # In honor of cardinality, Bluejay, and my office mate
  # who attacks his own reflection in my window all summer...
  module Cardinal
    class ExecutionError < StandardError; end
    class DocumentError < StandardError; end
  end
end

require_relative "cardinal/scalars"
require_relative "cardinal/breadth_executor"
require_relative "cardinal/depth_executor"
require_relative "cardinal/version"
