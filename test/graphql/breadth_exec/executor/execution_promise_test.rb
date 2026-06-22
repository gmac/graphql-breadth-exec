# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::ExecutionPromiseTest < Minitest::Test
  def test_then_dispatches_synchronously
    promise = GraphQL::BreadthExec::Executor::ExecutionPromise.new
    seen = nil

    chained = promise.then { |value| seen = value.upcase }
    promise.send(:resolve, "ok")

    assert_equal "OK", seen
    assert_predicate chained, :resolved?
    assert_equal "OK", chained.value
  end

  def test_then_adopts_nested_execution_promise
    inner = GraphQL::BreadthExec::Executor::ExecutionPromise.new
    outer = GraphQL::BreadthExec::Executor::ExecutionPromise.new { |resolve, _reject| resolve.call(inner) }

    refute_predicate outer, :resolved?
    inner.send(:resolve, "done")

    assert_predicate outer, :resolved?
    assert_equal "done", outer.value
  end

  def test_registry_tracks_chained_promises
    registry = []
    promise = GraphQL::BreadthExec::Executor::ExecutionPromise.new(registry: registry)
    chained = promise.then { |value| value }

    assert_equal [promise, chained], registry
  end

  def test_all_resolves_in_order
    first = GraphQL::BreadthExec::Executor::ExecutionPromise.new
    second = GraphQL::BreadthExec::Executor::ExecutionPromise.new
    all = GraphQL::BreadthExec::Executor::ExecutionPromise.all([first, second])

    second.send(:resolve, "b")
    first.send(:resolve, "a")

    assert_predicate all, :resolved?
    assert_equal ["a", "b"], all.value
  end
end
