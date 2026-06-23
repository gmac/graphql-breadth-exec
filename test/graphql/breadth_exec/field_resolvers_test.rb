# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::FieldResolversTest < Minitest::Test
  TEST_SCHEMA = GraphQL::Schema.from_definition(%|
    type Query {
      title: String
      chained: String
      fallback: String
      self: String
      value: String
    }
  |)

  class Machine
    def missing_value
      nil
    end

    def ping
      "pong"
    end
  end

  class HandleResolvedTestResolver < GraphQL::BreadthExec::FieldResolver
    def resolve(_exec_field, _context)
      []
    end
  end

  def test_hash_key_resolver_with_string_key
    result = execute(
      "{ title }",
      { "title" => "Do Androids Dream of Electric Sheep?" },
      "Query" => {
        "title" => GraphQL::BreadthExec::HashKeyResolver.new("title"),
      },
    )

    assert_equal(
      { "data" => { "title" => "Do Androids Dream of Electric Sheep?" } },
      result,
    )
  end

  def test_method_resolver_chains_methods
    result = execute(
      "{ chained }",
      " hello ",
      "Query" => {
        "chained" => GraphQL::BreadthExec::MethodResolver.new(:strip, :upcase, :reverse),
      },
    )

    assert_equal({ "data" => { "chained" => "OLLEH" } }, result)
  end

  def test_method_resolver_uses_fallback_when_chain_returns_nil
    result = execute(
      "{ fallback }",
      Machine.new,
      "Query" => {
        "fallback" => GraphQL::BreadthExec::MethodResolver.new(:missing_value, :upcase, fallback: "default"),
      },
    )

    assert_equal({ "data" => { "fallback" => "default" } }, result)
  end

  def test_method_resolver_uses_present_value_over_fallback
    result = execute(
      "{ fallback }",
      Machine.new,
      "Query" => {
        "fallback" => GraphQL::BreadthExec::MethodResolver.new(:ping, fallback: "default"),
      },
    )

    assert_equal({ "data" => { "fallback" => "pong" } }, result)
  end

  def test_self_resolver_returns_source_object
    result = execute(
      "{ self }",
      "source value",
      "Query" => {
        "self" => GraphQL::BreadthExec::SelfResolver.new,
      },
    )

    assert_equal({ "data" => { "self" => "source value" } }, result)
  end

  def test_value_resolver_returns_configured_value
    result = execute(
      "{ value }",
      Object.new,
      "Query" => {
        "value" => GraphQL::BreadthExec::ValueResolver.new("constant"),
      },
    )

    assert_equal({ "data" => { "value" => "constant" } }, result)
  end

  def test_handle_resolved_yields_array_directly
    resolver = HandleResolvedTestResolver.new
    input = ["a", "b", "c"]

    result = resolver.handle_resolved(input) { |values| values.map(&:upcase) }

    assert_equal ["A", "B", "C"], result
  end

  def test_handle_resolved_wraps_promise_with_then
    resolver = HandleResolvedTestResolver.new
    promise = GraphQL::BreadthExec::Executor::ExecutionPromise.new

    result = resolver.handle_resolved(promise) { |values| values.map(&:upcase) }

    assert_instance_of GraphQL::BreadthExec::Executor::ExecutionPromise, result
  end

  private

  def execute(document_string, root_object, resolvers)
    GraphQL::BreadthExec::Executor.new(
      TEST_SCHEMA,
      GraphQL.parse(document_string),
      resolvers: resolvers,
      root_object: root_object,
    ).result
  end
end
