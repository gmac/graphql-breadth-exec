# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::Executor::ErrorsTest < Minitest::Test
  def test_nullable_positional_errors
    document = %|{
      products(first: 3) {
        nodes {
          maybe
        }
      }
    }|

    source = {
      "products" => {
        "nodes" => [
          { "maybe" => "okay!" },
          { "maybe" => nil },
          { "maybe" => GraphQL::Cardinal::ExecutionError.new },
        ],
      },
    }

    expected = {
      "data" => {
        "products" => {
          "nodes" => [
            { "maybe" => "okay!" },
            { "maybe" => nil },
            { "maybe" => nil },
          ],
        },
      },
      "errors" => [{
        "message" => "An unknown error occurred",
        "path" => ["products", "nodes", 2, "maybe"],
      }],
    }

    assert_equal expected, breadth_exec(document, source)
  end

  def test_non_null_positional_errors
    document = %|{
      products(first: 3) {
        nodes {
          must
        }
      }
    }|

    source = {
      "products" => {
        "nodes" => [
          { "must" => "okay!" },
          { "must" => nil },
          { "must" => GraphQL::Cardinal::ExecutionError.new },
        ],
      },
    }

    expected = {
      "data" => {
        "products" => {
          "nodes" => nil,
        },
      },
      "errors" => [{
        "message" => "Failed to resolve expected value",
        "path" => ["products", "nodes", 1, "must"],
      }, {
        "message" => "An unknown error occurred",
        "path" => ["products", "nodes", 2, "must"],
      }],
    }

    assert_equal expected, breadth_exec(document, source)
  end
end
