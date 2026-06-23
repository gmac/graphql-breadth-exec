# frozen_string_literal: true

require "test_helper"

class GraphQL::Breadth::Incremental::ContextTest < Minitest::Test
  DeferredDelivery = GraphQL::Breadth::Incremental::DeferredDelivery
  DeferredExecutionScope = GraphQL::Breadth::Incremental::DeferredExecutionScope
  ExecutionScope = GraphQL::Breadth::Executor::ExecutionScope
  IncrementalContext = GraphQL::Breadth::Incremental::Context

  def test_completed_payloads_deduplicate_deliveries
    context = IncrementalContext.new(nil, data: {})
    delivery = DeferredDelivery.new(["hero"])

    assert_equal(
      [{ "id" => "0", "errors" => [{ "message" => "bad" }] }],
      context.completed_payloads(
        [delivery, delivery],
        errors_by_delivery: { delivery => [{ "message" => "bad" }] },
      ),
    )
    assert_equal [], context.completed_payloads([delivery])
  end

  def test_deferred_execution_scope_is_not_ready_when_base_scope_aborted
    executor = GraphQL::Breadth::Executor.new(
      SCHEMA,
      GraphQL.parse("{ noResolver }"),
      resolvers: BREADTH_RESOLVERS,
      root_object: {},
    )
    base_scope = ExecutionScope.new(
      executor: executor,
      parent_type: SCHEMA.query,
      selections: [],
      objects: [{}].freeze,
      results: [{}].freeze,
    )
    base_scope.executed = true

    deferred_scope = DeferredExecutionScope.new(
      base_scope: base_scope,
      field_selections: {},
      defer_usages: Set.new,
    )

    assert deferred_scope.ready?
    base_scope.abort!
    refute deferred_scope.ready?
  end
end
