# frozen_string_literal: true

require 'warning'
Gem.path.each do |path|
  # ignore warnings from auto-generated GraphQL lib code.
  Warning.ignore(/.*mismatched indentations.*/)
  Warning.ignore(/.*lib\/graphql\/language\/nodes.rb:.*/)
end

require 'bundler/setup'
Bundler.require(:default, :test)

require 'minitest/pride'
require 'minitest/autorun'
require 'minitest/stub_const'

require 'graphql/breadth_exec'
require 'graphql/batch'
require_relative './fixtures'

def breadth_exec(query, source, variables: {}, context: {}, tracers: [GraphQL::BreadthExec::Tracer.new])
  GraphQL::BreadthExec::Executor.new(
    SCHEMA,
    BREADTH_RESOLVERS,
    GraphQL.parse(query),
    source,
    tracers: tracers,
    variables: variables,
    context: context,
  ).perform
end
