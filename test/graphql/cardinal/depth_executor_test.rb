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
    document = GraphQL.parse(%|{
      products(first: 3) {
        nodes {
          id
          title
          variants(first: 5) {
            nodes {
              id
              title
            }
          }
        }
      }
    }|)

    executor = GraphQL::Cardinal::DepthExecutor.new(SCHEMA, DEPTH_RESOLVERS, document, SOURCE)
    result = executor.perform
    assert_equal SOURCE, result
  end
end
