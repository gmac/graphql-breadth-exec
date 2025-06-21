# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::Executor::ErrorsTest < Minitest::Test
  def test_nullable_positional_error_adds_path
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
          { "maybe" => GraphQL::Cardinal::ExecutionError.new("Not okay!") },
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
        "message" => "Not okay!",
        "path" => ["products", "nodes", 2, "maybe"],
      }],
    }

    assert_equal expected, breadth_exec(document, source)
  end

  def test_non_null_positional_error_adds_path_and_propagates
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
          { "must" => GraphQL::Cardinal::ExecutionError.new("Not okay!") },
        ],
      },
    }

    expected = {
      "data" => {
        "products" => { "nodes" => nil },
      },
      "errors" => [{
        "message" => "Not okay!",
        "path" => ["products", "nodes", 1, "must"],
      }],
    }

    assert_equal expected, breadth_exec(document, source)
  end

  def test_null_in_non_null_position_propagates
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
        ],
      },
    }

    expected = {
      "data" => {
        "products" => { "nodes" => nil },
      },
      "errors" => [{
        "message" => "Failed to resolve expected value",
        "path" => ["products", "nodes", 1, "must"],
      }],
    }

    assert_equal expected, breadth_exec(document, source)
  end
end
