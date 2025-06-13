# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::DepthExecutorTest < Minitest::Test
  DEPTH_RESOLVERS = {
    "Product" => {
      "id" => ->(obj) { obj["id"] },
      "title" => ->(obj) { obj["title"] },
      "variants" => ->(obj) { obj["variants"] },
    },
    "ProductConnection" => {
      "nodes" => ->(obj) { obj["nodes"] },
    },
    "Variant" => {
      "id" => ->(obj) { obj["id"] },
      "title" => ->(obj) { obj["title"] },
    },
    "VariantConnection" => {
      "nodes" => ->(obj) { obj["nodes"] },
    },
    "Query" => {
      "products" => ->(obj) { obj["products"] },
    },
  }.freeze

  def test_runs
    executor = GraphQL::Cardinal::DepthExecutor.new(SCHEMA, DEPTH_RESOLVERS, DOCUMENT, SOURCE)
    result = executor.perform
    puts executor.exec_count
    #pp result
    assert_equal SOURCE, result
  end
end
