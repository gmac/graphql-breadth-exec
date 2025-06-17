# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::BreadthExecutorTest < Minitest::Test
  BREADTH_ESOLVERS = {
    "Node" => {
      "id" => ->(objs, _args, _ctx) { objs.map { _1["id"] } },
      "__type__" => ->(obj, ctx) { ctx[:query].get_type(obj["__typename"]) },
    },
    "HasMetafields" => {
      "metafield" => ->(objs, args, _ctx) { objs.map { _1["metafield"] } },
      "__type__" => ->(obj, ctx) { ctx[:query].get_type(obj["__typename"]) },
    },
    "Metafield" => {
      "key" => ->(objs, args, _ctx) { objs.map { _1["key"] } },
      "value" => ->(objs, args, _ctx) { objs.map { _1["value"] } },
    },
    "Product" => {
      "id" => ->(objs, _args, _ctx) { objs.map { _1["id"] } },
      "title" => ->(objs, _args, _ctx) { objs.map { _1["title"] } },
      "variants" => ->(objs, _args, _ctx) { objs.map { _1["variants"] } },
      "metafield" => ->(objs, args, _ctx) { objs.map { _1["metafield"] } },
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
    "WriteValuePayload" => {
      "value" => ->(objs, _args, _ctx) { objs.map { _1["value"] } },
    },
    "Query" => {
      "products" => ->(objs, _args, _ctx) { objs.map { _1["products"] } },
      "nodes" => ->(objs, _args, _ctx) { objs.map { _1["nodes"] } },
      "node" => ->(objs, _args, _ctx) { objs.map { _1["node"] } },
    },
    "Mutation" => {
      "writeValue" => ->(objs, args, _ctx) {
        objs.each { _1["writeValue"]["value"] = args["value"] }
        objs.map { _1["writeValue"] }
      },
    },
  }.freeze

  def test_runs
    executor = GraphQL::Cardinal::BreadthExecutor.new(SCHEMA, BREADTH_ESOLVERS, DOCUMENT, SOURCE)
    assert_equal SOURCE, executor.perform
  end

  def test_follows_skip_directives
    document = GraphQL.parse(%|{
      products(first: 3) {
        nodes {
          id
          title @skip(if: true)
        }
      }
    }|)

    source = {
      "products" => {
        "nodes" => [
          { "id" => "Product/1" },
          { "id" => "Product/2" },
        ],
      },
    }

    executor = GraphQL::Cardinal::BreadthExecutor.new(SCHEMA, BREADTH_ESOLVERS, document, source)
    assert_equal source, executor.perform
  end

  def test_follows_include_directives
    document = GraphQL.parse(%|{
      products(first: 3) {
        nodes {
          id
          title @include(if: false)
        }
      }
    }|)

    source = {
      "products" => {
        "nodes" => [
          { "id" => "Product/1" },
          { "id" => "Product/2" },
        ],
      },
    }

    executor = GraphQL::Cardinal::BreadthExecutor.new(SCHEMA, BREADTH_ESOLVERS, document, source)
    assert_equal source, executor.perform
  end

  def test_aggregate_field_access
    document = GraphQL.parse(%|{
      node(id: "Product/1") {
        ... on Product {
          title
          metafield(key: "test") {
            key
          }
          metafield(key: "test") {
            value
          }
        }
      }
    }|)

    source = {
      "node" => {
        "title" => "Banana",
        "metafield" => { "key" => "test", "value" => "okay" },
        "__typename" => "Product",
      },
    }

    expected = {
      "node" => {
        "title" => "Banana",
        "metafield" => { "key" => "test", "value" => "okay" },
      },
    }

    executor = GraphQL::Cardinal::BreadthExecutor.new(SCHEMA, BREADTH_ESOLVERS, document, source)
    assert_equal expected, executor.perform
  end

  def test_aggregate_field_access_across_fragments
    document = GraphQL.parse(%|{
      node(id: "Product/1") {
        ... on Product {
          title
          metafield(key: "test") {
            key
          }
        }
        ...on HasMetafields {
          metafield(key: "test") {
            value
          }
        }
      }
    }|)

    source = {
      "node" => {
        "title" => "Banana",
        "metafield" => { "key" => "test", "value" => "okay" },
        "__typename" => "Product",
      },
    }

    expected = {
      "node" => {
        "title" => "Banana",
        "metafield" => { "key" => "test", "value" => "okay" },
      },
    }

    executor = GraphQL::Cardinal::BreadthExecutor.new(SCHEMA, BREADTH_ESOLVERS, document, source)
    assert_equal expected, executor.perform
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
    assert_equal expected, executor.perform
  end

  def test_abstract_type_list_access
    document = GraphQL.parse(%|{
      nodes(ids: ["Product/1", "Variant/1"]) {
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
    assert_equal expected, executor.perform
  end

  def test_serial_mutations
    document = GraphQL.parse(%|mutation{
      a: writeValue(value: "test1") {
        value
      }
      b: writeValue(value: "test2") {
        value
      }
      c: writeValue(value: "test3") {
        value
      }
    }|)

    source = {
      "writeValue" => { "value" => nil },
    }

    expected = {
      "a" => { "value" => "test1" },
      "b" => { "value" => "test2" },
      "c" => { "value" => "test3" },
    }

    executor = GraphQL::Cardinal::BreadthExecutor.new(SCHEMA, BREADTH_ESOLVERS, document, source)
    assert_equal expected, executor.perform
  end
end
