# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::Executor::FragmentsTest < Minitest::Test
  SOURCE = {
    "products" => {
      "nodes" => [{
        "title" => "Banana",
        "metafield" => { "key" => "test", "value" => "okay" },
      }],
    },
  }.freeze

  def test_selects_via_inline_fragments
    document = %|{
      products(first: 1) {
        nodes {
          ... on Product { title }
        }
      }
    }|

    expected = {
      "products" => {
        "nodes" => [{ "title" => "Banana" }],
      },
    }

    assert_equal expected, breadth_exec(document, SOURCE).dig("data")
  end

  def test_selects_via_fragment_spreads
    document = %|{
      products(first: 1) {
        nodes {
          ... ProductAttrs
        }
      }
    }
    fragment ProductAttrs on Product {
      title
    }|

    expected = {
      "products" => {
        "nodes" => [{ "title" => "Banana" }],
      },
    }

    assert_equal expected, breadth_exec(document, SOURCE).dig("data")
  end

  def test_selects_via_nested_fragments
    document = %|{
      products(first: 1) {
        nodes {
          ... on Product {
            ... ProductAttrs
          }
        }
      }
    }
    fragment ProductAttrs on Product {
      ... on Product { title }
    }|

    expected = {
      "products" => {
        "nodes" => [{ "title" => "Banana" }],
      },
    }

    assert_equal expected, breadth_exec(document, SOURCE).dig("data")
  end

  def test_selects_via_abstract_fragments
    document = %|{
      products(first: 1) {
        nodes {
          ... on HasMetafields {
            metafield(key: "test") { key value }
          }
        }
      }
    }|

    expected = {
      "products" => {
        "nodes" => [{
          "metafield" => { "key" => "test", "value" => "okay" },
        }],
      },
    }

    assert_equal expected, breadth_exec(document, SOURCE).dig("data")
  end
end
