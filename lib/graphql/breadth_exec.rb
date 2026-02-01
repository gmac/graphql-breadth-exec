# frozen_string_literal: true

require "graphql"

module GraphQL
  module BreadthExec
    EMPTY_OBJECT = {}.freeze
  end
end

require_relative "breadth_exec/errors"
require_relative "breadth_exec/promise"
require_relative "breadth_exec/loader"
require_relative "breadth_exec/tracer"
require_relative "breadth_exec/field_resolvers"
require_relative "breadth_exec/introspection"
require_relative "breadth_exec/executor"
require_relative "breadth_exec/version"
