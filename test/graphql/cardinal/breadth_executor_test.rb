# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::BreadthExecutorTest < Minitest::Test
  BREADTH_ESOLVERS = {
    "Product" => {
      "id" => ->(objs) { objs.map { _1["id"] } },
      "title" => ->(objs) { objs.map { _1["title"] } },
      "variants" => ->(objs) { objs.map { _1["variants"] } },
    },
    "ProductConnection" => {
      "nodes" => ->(objs) { objs.map { _1["nodes"] } },
    },
    "Variant" => {
      "id" => ->(objs) { objs.map { _1["id"] } },
      "title" => ->(objs) { objs.map { _1["title"] } },
    },
    "VariantConnection" => {
      "nodes" => ->(objs) { objs.map { _1["nodes"] } },
    },
    "Query" => {
      "products" => ->(objs) { objs.map { _1["products"] } },
    },
  }.freeze

  def test_runs
    executor = GraphQL::Cardinal::BreadthExecutor.new(SCHEMA, BREADTH_ESOLVERS, DOCUMENT, SOURCE)
    result = executor.perform
    pp result
    assert_equal SOURCE, result
  end
end
