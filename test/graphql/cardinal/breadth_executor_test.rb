# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::ExecutorTest < Minitest::Test
  def test_runs
    assert_equal BASIC_SOURCE, breadth_exec(BASIC_DOCUMENT, BASIC_SOURCE).dig("data")
  end

  def test_follows_skip_directives
    document = %|{
      products(first: 3) {
        nodes {
          id
          title @skip(if: true)
        }
      }
    }|

    source = {
      "products" => {
        "nodes" => [
          { "id" => "Product/1" },
          { "id" => "Product/2" },
        ],
      },
    }

    assert_equal source, breadth_exec(document, source).dig("data")
  end

  def test_follows_include_directives
    document = %|{
      products(first: 3) {
        nodes {
          id
          title @include(if: false)
        }
      }
    }|

    source = {
      "products" => {
        "nodes" => [
          { "id" => "Product/1" },
          { "id" => "Product/2" },
        ],
      },
    }

    assert_equal source, breadth_exec(document, source).dig("data")
  end

  def test_aggregate_field_access
    document = %|{
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
    }|

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

    assert_equal expected, breadth_exec(document, source).dig("data")
  end

  def test_aggregate_field_access_across_fragments
    document = %|{
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
    }|

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

    assert_equal expected, breadth_exec(document, source).dig("data")
  end

  def test_abstract_type_object_access
    document = %|{
      node(id: "Product/1") {
        ... on Product { id }
      }
    }|

    source = {
      "node" => { "id" => "Product/1", "__typename" => "Product" },
    }

    expected = {
      "node" => { "id" => "Product/1" },
    }

    assert_equal expected, breadth_exec(document, source).dig("data")
  end

  def test_abstract_type_list_access
    document = %|{
      nodes(ids: ["Product/1", "Variant/1"]) {
        ... on Product {
          id
        }
        ... on Variant {
          title
        }
      }
    }|

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

    assert_equal expected, breadth_exec(document, source).dig("data")
  end

  def test_serial_mutations
    document = %|mutation {
      a: writeValue(value: "test1") {
        value
      }
      b: writeValue(value: "test2") {
        value
      }
      c: writeValue(value: "test3") {
        value
      }
    }|

    source = {
      "writeValue" => { "value" => nil },
    }

    expected = {
      "a" => { "value" => "test1" },
      "b" => { "value" => "test2" },
      "c" => { "value" => "test3" },
    }

    assert_equal expected, breadth_exec(document, source).dig("data")
  end
end
