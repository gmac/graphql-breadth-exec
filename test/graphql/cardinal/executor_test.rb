# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::ExecutorTest < Minitest::Test
  def test_resolves_basic_query
    assert_equal BASIC_SOURCE, breadth_exec(BASIC_DOCUMENT, BASIC_SOURCE).dig("data")
  end

  def test_resolves_typename_field
    document = %|{
      products(first: 1) {
        nodes {
          __typename
        }
      }
      node(id: "Product/1") {
        __typename
      }
    }|

    source = {
      "products" => { "nodes" => [{}] },
      "node" => { "__typename__" => "Product" },
    }

    expected = {
      "products" => {
        "nodes" => [{ "__typename" => "Product" }],
      },
      "node" => { "__typename" => "Product" },
    }

    assert_equal expected, breadth_exec(document, source).dig("data")
  end

  def test_mutations_run_serially
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

  def test_subscriptions_not_supported
    document = %|subscription {
      onWriteValue { value }
    }|

    error = assert_raises(GraphQL::Cardinal::DocumentError) do
      breadth_exec(document, {})
    end

    assert_equal "Unsupported operation type: subscription", error.message
  end

  def test_raises_not_implemented_for_missing_resolvers
    document = %|{ noResolver }|

    error = assert_raises(NotImplementedError) do
      breadth_exec(document, {})
    end

    assert_equal "No field resolver for 'Query.noResolver'", error.message
  end
end
