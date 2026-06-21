# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::ErrorFormatterTest < Minitest::Test
  TEST_RESOLVERS = {
    "Node" => {
      "id" => GraphQL::BreadthExec::HashKeyResolver.new("id"),
      "__type__" => ->(obj, ctx) { ctx.types.type(obj["__typename__"]) },
    },
    "Test" => {
      "id" => GraphQL::BreadthExec::HashKeyResolver.new("id"),
      "req" => GraphQL::BreadthExec::HashKeyResolver.new("req"),
      "opt" => GraphQL::BreadthExec::HashKeyResolver.new("opt"),
    },
    "Query" => {
      "node" => GraphQL::BreadthExec::HashKeyResolver.new("node"),
      "test" => GraphQL::BreadthExec::HashKeyResolver.new("test"),
      "reqField" => GraphQL::BreadthExec::HashKeyResolver.new("reqField"),
    },
  }.freeze

  def test_bubbles_null_for_single_object_scopes
    schema = "type Test { req: String! opt: String } type Query { test: Test }"
    source = { "test" => { "req" => nil, "opt" => "yes" } }

    expected = {
      "errors" => [{
        "message" => "Cannot return null for non-nullable field Test.req",
        "locations" => [{ "line" => 1, "column" => 10 }],
        "path" => ["test", "req"],
        "extensions" => { "code" => "INVALID_NULL" },
      }],
      "data" => { "test" => nil },
    }

    assert_equal expected, exec_test(schema, "{ test { req opt } }", source)
  end

  def test_bubbles_null_for_list_elements
    schema = "type Test { req: String! opt: String } type Query { test: [Test] }"
    source = {
      "test" => [
        { "req" => "yes", "opt" => nil },
        { "req" => nil, "opt" => "yes" },
      ],
    }

    expected = {
      "errors" => [{
        "message" => "Cannot return null for non-nullable field Test.req",
        "locations" => [{ "line" => 1, "column" => 10 }],
        "path" => ["test", 1, "req"],
        "extensions" => { "code" => "INVALID_NULL" },
      }],
      "data" => { "test" => [{ "req" => "yes", "opt" => nil }, nil] },
    }

    assert_equal expected, exec_test(schema, "{ test { req opt } }", source)
  end

  def test_bubbles_null_through_nested_required_list_scopes
    schema = "type Test { req: String! opt: String } type Query { test: [[Test!]!]! }"
    source = {
      "test" => [
        [{ "req" => "yes", "opt" => nil }],
        [{ "req" => nil, "opt" => "yes" }],
      ],
    }

    expected = {
      "errors" => [{
        "message" => "Cannot return null for non-nullable field Test.req",
        "locations" => [{ "line" => 1, "column" => 10 }],
        "path" => ["test", 1, 0, "req"],
        "extensions" => { "code" => "INVALID_NULL" },
      }],
      "data" => nil,
    }

    assert_equal expected, exec_test(schema, "{ test { req opt } }", source)
  end

  def test_inline_errors_in_null_positions_report
    schema = "type Test { req: String! opt: String } type Query { test: [Test] }"
    source = {
      "test" => [
        { "req" => "yes", "opt" => nil },
        { "req" => "yes", "opt" => GraphQL::BreadthExec::ExecutionError.new("Not okay!") },
      ],
    }

    expected = {
      "errors" => [{
        "message" => "Not okay!",
        "locations" => [{ "line" => 1, "column" => 14 }],
        "path" => ["test", 1, "opt"],
      }],
      "data" => {
        "test" => [
          { "req" => "yes", "opt" => nil },
          { "req" => "yes", "opt" => nil },
        ],
      },
    }

    assert_equal expected, exec_test(schema, "{ test { req opt } }", source)
  end

  def test_multiple_locations_for_duplicate_field_selections
    schema = "type Query { reqField: String! }"
    source = { "reqField" => nil }

    query = <<~GRAPHQL
      {
        reqField
        reqField
      }
    GRAPHQL

    expected = {
      "errors" => [{
        "message" => "Cannot return null for non-nullable field Query.reqField",
        "locations" => [
          { "line" => 2, "column" => 3 },
          { "line" => 3, "column" => 3 },
        ],
        "path" => ["reqField"],
        "extensions" => { "code" => "INVALID_NULL" },
      }],
      "data" => nil,
    }

    assert_equal expected, exec_test(schema, query, source)
  end

  def test_formats_errors_with_extensions
    schema = "type Query { test: String! }"
    source = {
      "test" => GraphQL::BreadthExec::ExecutionError.new("Not okay!", extensions: {
        "code" => "TEST",
        reason: "sorry",
      }),
    }

    expected = {
      "errors" => [{
        "message" => "Not okay!",
        "locations" => [{ "line" => 1, "column" => 3 }],
        "path" => ["test"],
        "extensions" => { "code" => "TEST", "reason" => "sorry" },
      }],
      "data" => nil,
    }

    assert_equal expected, exec_test(schema, "{ test }", source)
  end

  def test_pushes_original_errors_into_context
    schema = "type Query { test: String! }"
    cause = StandardError.new("Boom.")
    source = {
      "test" => GraphQL::BreadthExec::ExecutionError.new("Not okay!", cause: cause),
    }

    result = exec_test(schema, "{ test }", source) do |executor|
      assert_equal 1, executor.context.errors.length
      assert_same cause, executor.context.errors.first
    end

    assert_equal "Not okay!", result.dig("errors", 0, "message")
    assert_equal ["test"], result.dig("errors", 0, "path")
  end

  def test_formats_error_message_for_non_null_list_items
    schema = "type Test { req: String! } type Query { test: [Test!]! }"
    source = { "test" => [nil] }

    expected = {
      "errors" => [{
        "message" => "Cannot return null for non-nullable element of type 'Test!' for Query.test",
        "locations" => [{ "line" => 1, "column" => 3 }],
        "path" => ["test", 0],
        "extensions" => { "code" => "INVALID_NULL" },
      }],
      "data" => nil,
    }

    assert_equal expected, exec_test(schema, "{ test { req } }", source)
  end

  private

  def exec_test(schema, query, source)
    executor = GraphQL::BreadthExec::Executor.new(
      GraphQL::Schema.from_definition(schema),
      GraphQL.parse(query),
      resolvers: TEST_RESOLVERS,
      root_object: source,
    )

    result = executor.result
    yield executor if block_given?
    result
  end
end
