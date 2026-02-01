# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::AbstractsTest < Minitest::Test
  def test_abstract_type_object_access
    document = %|{
      node(id: "Product/1") {
        ... on Product { id }
        __typename
      }
    }|

    source = {
      "node" => { "id" => "Product/1", "__typename__" => "Product" },
    }

    expected = {
      "node" => { "id" => "Product/1", "__typename" => "Product" },
    }

    assert_equal expected, breadth_exec(document, source).dig("data")
  end

  def test_abstract_type_list_access
    document = %|{
      nodes(ids: ["Product/1", "Variant/1"]) {
        __typename
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
        { "id" => "Product/1", "title" => "Product 1", "__typename__" => "Product" },
        { "id" => "Variant/1", "title" => "Variant 1", "__typename__" => "Variant" },
      ],
    }

    expected = {
      "nodes" => [
        { "id" => "Product/1", "__typename" => "Product" },
        { "title" => "Variant 1", "__typename" => "Variant" },
      ],
    }

    assert_equal expected, breadth_exec(document, source).dig("data")
  end
end
