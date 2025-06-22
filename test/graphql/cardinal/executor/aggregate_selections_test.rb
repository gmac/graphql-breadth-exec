# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::Executor::AggregateSelectionsTest < Minitest::Test
  NODE_SOURCE = {
    "node" => {
      "title" => "Banana",
      "metafield" => { "key" => "test", "value" => "okay" },
      "__typename__" => "Product",
    },
  }.freeze

  NODE_EXPECTED = {
    "node" => {
      "title" => "Banana",
      "metafield" => { "key" => "test", "value" => "okay" },
    },
  }.freeze

  def test_aggregate_field_selections
    document = %|{
      products(first: 1) {
        nodes {
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
      "products" => {
        "nodes" => [{
          "title" => "Banana",
          "metafield" => { "key" => "test", "value" => "okay" },
        }],
      },
    }

    assert_equal source, breadth_exec(document, source).dig("data")
  end

  def test_aggregate_field_access_across_inline_fragments
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

    assert_equal NODE_EXPECTED, breadth_exec(document, NODE_SOURCE).dig("data")
  end

  def test_aggregate_field_access_across_fragment_spreads
    document = %|{
      node(id: "Product/1") {
        ... ProductAttrs
        ... HasMetafieldsAttrs
      }
    }
    fragment ProductAttrs on Product {
      title
      metafield(key: "test") {
        key
      }
    }
    fragment HasMetafieldsAttrs on HasMetafields {
      metafield(key: "test") {
        value
      }
    }|

    assert_equal NODE_EXPECTED, breadth_exec(document, NODE_SOURCE).dig("data")
  end
end
