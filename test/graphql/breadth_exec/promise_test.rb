# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::PromiseTest < Minitest::Test
  def setup
    @promise = GraphQL::BreadthExec::Promise.new
  end

  def test_initial_state_is_pending
    assert_predicate @promise, :pending?
    refute_predicate @promise, :resolved?
    refute_predicate @promise, :rejected?
    assert_nil @promise.value
    assert_nil @promise.reason
  end

  def test_resolve_changes_state_to_fulfilled
    @promise.send(:resolve, "test value")

    assert_predicate @promise, :resolved?
    refute_predicate @promise, :pending?
    refute_predicate @promise, :rejected?
    assert_equal "test value", @promise.value
    assert_nil @promise.reason
  end

  def test_reject_changes_state_to_rejected
    error = StandardError.new("test error")
    @promise.send(:reject, error)

    assert_predicate @promise, :rejected?
    refute_predicate @promise, :pending?
    refute_predicate @promise, :resolved?
    assert_nil @promise.value
    assert_equal error, @promise.reason
  end

  def test_cannot_resolve_already_resolved_promise
    @promise.send(:resolve, "first value")
    @promise.send(:resolve, "second value")

    assert_equal "first value", @promise.value
  end

  def test_cannot_reject_already_resolved_promise
    @promise.send(:resolve, "value")
    error = StandardError.new("error")
    @promise.send(:reject, error)

    assert_predicate @promise, :resolved?
    assert_equal "value", @promise.value
    assert_nil @promise.reason
  end

  def test_cannot_resolve_already_rejected_promise
    error = StandardError.new("error")
    @promise.send(:reject, error)
    @promise.send(:resolve, "value")

    assert_predicate @promise, :rejected?
    assert_equal error, @promise.reason
    assert_nil @promise.value
  end

  def test_cannot_reject_already_rejected_promise
    error1 = StandardError.new("first error")
    error2 = StandardError.new("second error")
    @promise.send(:reject, error1)
    @promise.send(:reject, error2)

    assert_equal error1, @promise.reason
  end

  def test_constructor_with_block_resolves
    promise = GraphQL::BreadthExec::Promise.new do |resolve, reject|
      resolve.call("test value")
    end

    assert_predicate promise, :resolved?
    assert_equal "test value", promise.value
  end

  def test_constructor_with_block_rejects
    error = StandardError.new("test error")
    promise = GraphQL::BreadthExec::Promise.new do |resolve, reject|
      reject.call(error)
    end

    assert_predicate promise, :rejected?
    assert_equal error, promise.reason
  end

  def test_constructor_with_block_catches_exceptions
    promise = GraphQL::BreadthExec::Promise.new do |resolve, reject|
      raise StandardError.new("test error")
    end

    assert_predicate promise, :rejected?
    assert_instance_of StandardError, promise.reason
    assert_equal "test error", promise.reason.message
  end

  def test_then_with_fulfilled_promise
    @promise.send(:resolve, "original value")

    result_promise = @promise.then { |value| "transformed: #{value}" }

    assert_predicate result_promise, :resolved?
    assert_equal "transformed: original value", result_promise.value
  end

  def test_then_with_rejected_promise
    error = StandardError.new("original error")
    @promise.send(:reject, error)

    result_promise = @promise.then(
      ->(value) { "should not be called" },
      ->(reason) { "handled: #{reason.message}" }
    )

    assert_predicate result_promise, :resolved?
    assert_equal "handled: original error", result_promise.value
  end

  def test_then_with_pending_promise
    fulfilled_called = false
    rejected_called = false

    result_promise = @promise.then(
      ->(value) { fulfilled_called = true; "fulfilled: #{value}" },
      ->(reason) { rejected_called = true; "rejected: #{reason.message}" }
    )

    assert_predicate result_promise, :pending?
    refute fulfilled_called
    refute rejected_called

    @promise.send(:resolve, "test value")

    assert_predicate result_promise, :resolved?
    assert_equal "fulfilled: test value", result_promise.value
    assert fulfilled_called
    refute rejected_called
  end

  def test_then_with_pending_promise_rejected
    fulfilled_called = false
    rejected_called = false

    result_promise = @promise.then(
      ->(value) { fulfilled_called = true; "fulfilled: #{value}" },
      ->(reason) { rejected_called = true; "rejected: #{reason.message}" }
    )

    error = StandardError.new("test error")
    @promise.send(:reject, error)

    assert_predicate result_promise, :resolved?
    assert_equal "rejected: test error", result_promise.value
    refute fulfilled_called
    assert rejected_called
  end

  def test_then_catches_exceptions_in_fulfilled_handler
    @promise.send(:resolve, "test value")

    result_promise = @promise.then { |value| raise StandardError.new("handler error") }

    assert_predicate result_promise, :rejected?
    assert_instance_of StandardError, result_promise.reason
    assert_equal "handler error", result_promise.reason.message
  end

  def test_then_catches_exceptions_in_rejected_handler
    @promise.send(:reject, StandardError.new("original error"))

    result_promise = @promise.then(
      ->(value) { "should not be called" },
      ->(reason) { raise StandardError.new("handler error") }
    )

    assert_predicate result_promise, :rejected?
    assert_instance_of StandardError, result_promise.reason
    assert_equal "handler error", result_promise.reason.message
  end

  def test_then_returns_promise_from_fulfilled_handler
    inner_promise = GraphQL::BreadthExec::Promise.new
    @promise.send(:resolve, "test value")

    result_promise = @promise.then { |value| inner_promise }

    assert_predicate result_promise, :pending?

    inner_promise.send(:resolve, "inner value")

    assert_predicate result_promise, :resolved?
    assert_equal "inner value", result_promise.value
  end

  def test_then_returns_promise_from_rejected_handler
    inner_promise = GraphQL::BreadthExec::Promise.new
    @promise.send(:reject, StandardError.new("original error"))

    result_promise = @promise.then(
      ->(value) { "should not be called" },
      ->(reason) { inner_promise }
    )

    assert_predicate result_promise, :pending?

    inner_promise.send(:resolve, "recovered value")

    assert_predicate result_promise, :resolved?
    assert_equal "recovered value", result_promise.value
  end

  def test_then_requires_fulfilled_handler_or_block
    assert_raises ArgumentError do
      @promise.then
    end
  end

  def test_then_forbids_both_fulfilled_handler_and_block
    assert_raises ArgumentError do
      @promise.then(->(v) { v }) { |v| v }
    end
  end

  def test_catch_handles_rejected_promise
    error = StandardError.new("test error")
    @promise.send(:reject, error)

    result_promise = @promise.catch { |reason| "caught: #{reason.message}" }

    assert_predicate result_promise, :resolved?
    assert_equal "caught: test error", result_promise.value
  end

  def test_catch_passes_through_resolved_promise
    @promise.send(:resolve, "test value")

    result_promise = @promise.catch { |reason| "should not be called" }

    assert_predicate result_promise, :resolved?
    assert_equal "test value", result_promise.value
  end

    def test_promise_resolve_creates_resolved_promise
    result_promise = GraphQL::BreadthExec::Promise.resolve("test value")

    assert_predicate result_promise, :resolved?
    assert_equal "test value", result_promise.value
  end

  def test_all_with_empty_array
    result_promise = GraphQL::BreadthExec::Promise.all([])

    assert_predicate result_promise, :resolved?
    assert_equal [], result_promise.value
  end

  def test_all_with_single_resolved_promise
    promise1 = GraphQL::BreadthExec::Promise.new
    promise1.send(:resolve, "value1")

    result_promise = GraphQL::BreadthExec::Promise.all([promise1])

    assert_predicate result_promise, :resolved?
    assert_equal ["value1"], result_promise.value
  end

  def test_all_with_multiple_resolved_promises
    promise1 = GraphQL::BreadthExec::Promise.new
    promise2 = GraphQL::BreadthExec::Promise.new
    promise3 = GraphQL::BreadthExec::Promise.new

    promise1.send(:resolve, "value1")
    promise2.send(:resolve, "value2")
    promise3.send(:resolve, "value3")

    result_promise = GraphQL::BreadthExec::Promise.all([promise1, promise2, promise3])

    assert_predicate result_promise, :resolved?
    assert_equal ["value1", "value2", "value3"], result_promise.value
  end

  def test_all_with_pending_promises
    promise1 = GraphQL::BreadthExec::Promise.new
    promise2 = GraphQL::BreadthExec::Promise.new
    promise3 = GraphQL::BreadthExec::Promise.new

    result_promise = GraphQL::BreadthExec::Promise.all([promise1, promise2, promise3])

    assert_predicate result_promise, :pending?

    promise1.send(:resolve, "value1")
    assert_predicate result_promise, :pending?

    promise2.send(:resolve, "value2")
    assert_predicate result_promise, :pending?

    promise3.send(:resolve, "value3")
    assert_predicate result_promise, :resolved?
    assert_equal ["value1", "value2", "value3"], result_promise.value
  end

  def test_all_rejects_if_any_promise_rejects
    promise1 = GraphQL::BreadthExec::Promise.new
    promise2 = GraphQL::BreadthExec::Promise.new
    promise3 = GraphQL::BreadthExec::Promise.new

    result_promise = GraphQL::BreadthExec::Promise.all([promise1, promise2, promise3])

    promise1.send(:resolve, "value1")
    error = StandardError.new("test error")
    promise2.send(:reject, error)
    promise3.send(:resolve, "value3")

    assert_predicate result_promise, :rejected?
    assert_equal error, result_promise.reason
  end

  def test_all_maintains_order
    promise1 = GraphQL::BreadthExec::Promise.new
    promise2 = GraphQL::BreadthExec::Promise.new
    promise3 = GraphQL::BreadthExec::Promise.new

    result_promise = GraphQL::BreadthExec::Promise.all([promise1, promise2, promise3])

    # Resolve in different order
    promise3.send(:resolve, "value3")
    promise1.send(:resolve, "value1")
    promise2.send(:resolve, "value2")

    assert_predicate result_promise, :resolved?
    assert_equal ["value1", "value2", "value3"], result_promise.value
  end

  def test_chaining_then_calls
    @promise.send(:resolve, 1)

    result_promise = @promise
      .then { |value| value + 1 }
      .then { |value| value * 2 }
      .then { |value| "result: #{value}" }

    assert_predicate result_promise, :resolved?
    assert_equal "result: 4", result_promise.value
  end

  def test_error_propagation_through_chain
    @promise.send(:resolve, "test")

    result_promise = @promise
      .then { |value| raise StandardError.new("chain error") }
      .then { |value| "should not be called" }
      .catch { |error| "caught: #{error.message}" }

    assert_predicate result_promise, :resolved?
    assert_equal "caught: chain error", result_promise.value
  end
end
