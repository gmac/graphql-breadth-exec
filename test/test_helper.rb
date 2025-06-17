# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

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
require 'graphql/cardinal'
require_relative './fixtures'

def breadth_exec(query, source, variables: {}, context: {})
  executor = GraphQL::Cardinal::BreadthExecutor.new(SCHEMA, BREADTH_ESOLVERS, GraphQL.parse(query), source)
  executor.perform
end

def depth_exec(query, source, variables: {}, context: {})
  executor = GraphQL::Cardinal::DepthExecutor.new(SCHEMA, DEPTH_RESOLVERS, GraphQL.parse(query), source)
  executor.perform
end
