# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::BreadthExecutorTest < Minitest::Test
  BREADTH_ESOLVERS = {
    "Node" => {
      "id" => ->(objs, _args, _ctx) { objs.map { _1["id"] } },
      "__type__" => ->(obj, ctx) { ctx[:query].get_type(obj["__typename"]) },
    },
    "Product" => {
      "id" => ->(objs, _args, _ctx) { objs.map { _1["id"] } },
      "title" => ->(objs, _args, _ctx) { objs.map { _1["title"] } },
      "variants" => ->(objs, _args, _ctx) { objs.map { _1["variants"] } },
    },
    "ProductConnection" => {
      "nodes" => ->(objs, _args, _ctx) { objs.map { _1["nodes"] } },
    },
    "Variant" => {
      "id" => ->(objs, _args, _ctx) { objs.map { _1["id"] } },
      "title" => ->(objs, _args, _ctx) { objs.map { _1["title"] } },
    },
    "VariantConnection" => {
      "nodes" => ->(objs, _args, _ctx) { objs.map { _1["nodes"] } },
    },
    "Query" => {
      "products" => ->(objs, _args, _ctx) { objs.map { _1["products"] } },
      "nodes" => ->(objs, _args, _ctx) { objs.map { _1["nodes"] } },
      "node" => ->(objs, _args, _ctx) { objs.map { _1["node"] } },
    },
  }.freeze

  def test_runs
    executor = GraphQL::Cardinal::BreadthExecutor.new(SCHEMA, BREADTH_ESOLVERS, DOCUMENT, SOURCE)
    result = executor.perform
    assert_equal SOURCE, result
  end

  def test_abstract_type_list_access
    document = GraphQL.parse(%|{
      nodes(ids: $ids) {
        ... on Product {
          id
        }
        ... on Variant {
          title
        }
      }
    }|)

    source = {
      "nodes" => [
        { "id" => "Product/1", "title" => "Product 1", "__typename" => "Product" },
        { "id" => "Variant/1", "title" => "Variant 1", "__typename" => "Variant" },
      ],
    }

    expected = {
      "nodes" => [
        { "id" => "Product/1" },
        { "title" => "Variant 1" },
      ],
    }

    executor = GraphQL::Cardinal::BreadthExecutor.new(SCHEMA, BREADTH_ESOLVERS, document, source)
    result = executor.perform
    pp result
    assert_equal expected, result
  end

  def test_abstract_type_object_access
    document = GraphQL.parse(%|{
      node(id: "Product/1") {
        ... on Product { id }
      }
    }|)

    source = {
      "node" => { "id" => "Product/1", "__typename" => "Product" },
    }

    expected = {
      "node" => { "id" => "Product/1" },
    }

    executor = GraphQL::Cardinal::BreadthExecutor.new(SCHEMA, BREADTH_ESOLVERS, document, source)
    result = executor.perform
    pp result
    assert_equal expected, result
  end
end
