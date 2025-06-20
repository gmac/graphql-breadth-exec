# frozen_string_literal: true

require "graphql"

module GraphQL
  # In honor of cardinality, Bluejay, and my office mate
  # who attacks his own reflection in my window all summer...
  module Cardinal
    EMPTY_OBJECT = {}.freeze
  end
end

require_relative "cardinal/errors"
require_relative "cardinal/promise"
require_relative "cardinal/loader"
require_relative "cardinal/tracer"
require_relative "cardinal/field_resolvers"
require_relative "cardinal/executor"
require_relative "cardinal/version"
