# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::ExecutorTest < Minitest::Test
  SCHEMA = GraphQL::Schema.from_definition(%|
    type Product {
      id: ID!
      title: String
      variants(first: Int!): VariantConnection
    }

    type ProductConnection {
      nodes: [Product!]!
    }

    type Variant {
      id: ID!
      title: String
    }

    type VariantConnection {
      nodes: [Variant!]!
    }

    type Query {
      products(first: Int): ProductConnection
    }
  |)

  DOCUMENT = GraphQL.parse(%|{
    products(first: 3) {
      nodes {
        id
        ... { title }
        variants(first: 5) {
          nodes {
            id
            title
          }
        }
      }
    }
  }|)

  SOURCE = {
    "products" => {
      "nodes" => [{
        "id" => "1",
        "title" => "Apple",
        "variants" => {
          "nodes" => [
            { "id" => "1", "title" => "Large" },
            { "id" => "2", "title" => "Small" },
          ],
        },
      }, {
        "id" => "2",
        "title" => "Banana",
        "variants" => {
          "nodes" => [
            { "id" => "3", "title" => "Large" },
            { "id" => "4", "title" => "Small" },
          ],
        },
      }],
    },
  }

  RESOLVERS = {
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
    executor = GraphQL::Cardinal::Executor.new(SCHEMA, RESOLVERS, DOCUMENT, SOURCE)
    result = executor.perform
    pp result
    assert_equal SOURCE, result
  end
end
