# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::ExecutionErrorsTest < Minitest::Test
  def setup
    @exec_field = Object.new
    @other_exec_field = Object.new
  end

  def test_execution_error_from_returns_same_unreported_error_instance
    err = GraphQL::BreadthExec::ExecutionError.from(GraphQL::BreadthExec::UNREPORTED_ERROR, exec_field: @exec_field)

    assert_same GraphQL::BreadthExec::UNREPORTED_ERROR, err
    assert_nil err.exec_field
    assert_nil err.cause
  end

  def test_execution_error_from_wraps_graphql_execution_error
    ext = { "code" => "WHOOPS" }
    gem_err = GraphQL::ExecutionError.new("Whoops", extensions: ext)
    err = GraphQL::BreadthExec::ExecutionError.from(gem_err, exec_field: @exec_field)

    assert_equal "Whoops", err.message
    assert_equal ext, err.extensions
    assert_same @exec_field, err.exec_field
    assert_same gem_err, err.cause
  end

  def test_execution_error_from_dups_execution_error_when_exec_field_differs
    original = GraphQL::BreadthExec::ExecutionError.new("Whoops", exec_field: @other_exec_field)
    err = GraphQL::BreadthExec::ExecutionError.from(original, exec_field: @exec_field)

    refute_same original, err
    assert_equal "Whoops", err.message
    assert_same @exec_field, err.exec_field
  end

  def test_execution_error_from_preserves_execution_error_set_type
    original = GraphQL::BreadthExec::ExecutionErrorSet.new("Combined errors", exec_field: @other_exec_field)
    original.add_error("Error 1")
    original.add_error("Error 2")
    err = GraphQL::BreadthExec::ExecutionError.from(original, exec_field: @exec_field)

    assert_instance_of GraphQL::BreadthExec::ExecutionErrorSet, err
    assert_equal 2, err.errors.size
    assert_same @exec_field, err.exec_field
  end

  def test_input_error_keeps_input_path_when_wrapped
    original = GraphQL::BreadthExec::InputError.new("Invalid input", path: ["field", "input"])
    err = GraphQL::BreadthExec::ExecutionError.from(original, exec_field: @exec_field)

    assert_instance_of GraphQL::BreadthExec::InputError, err
    assert_equal ["field", "input"], err.path
    assert_same @exec_field, err.exec_field
  end

  def test_result_count_mismatch_error_message
    exec_field = Struct.new(:path).new(["widget"])
    err = GraphQL::BreadthExec::ResultCountMismatchError.new(exec_field:, expected_count: 1, actual_count: 3)

    assert_equal 1, err.expected_count
    assert_equal 3, err.actual_count
    assert_equal "Incorrect number of results for field `widget`. Expected 1, got 3.", err.message
  end
end
