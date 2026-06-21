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
require_relative './star_wars_fixtures'

def breadth_exec(query, source, variables: {}, context: {}, tracers: [GraphQL::BreadthExec::Tracer.new])
  GraphQL::BreadthExec::Executor.new(
    SCHEMA,
    GraphQL.parse(query),
    resolvers: BREADTH_RESOLVERS,
    root_object: source,
    tracers: tracers,
    variables: variables,
    context: context,
  ).result
end

def assert_error_reported(expected_class, &block)
  original_handler = GraphQL::BreadthExec.on_report_error
  reported_error = nil

  GraphQL::BreadthExec.on_report_error = ->(error) do
    reported_error = error
  end

  yield

  refute_nil(reported_error, "No error reported")
  raise StandardError, "No error reported" if reported_error.nil?

  assert_equal(expected_class, reported_error.class)
  reported_error
ensure
  GraphQL::BreadthExec.on_report_error = original_handler
end
