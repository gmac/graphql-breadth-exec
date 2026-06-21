# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::SubscriptionsTest < Minitest::Test
  SUBSCRIPTION_SCHEMA = GraphQL::Schema.from_definition(%|
    schema {
      query: Query
      subscription: Subscription
    }

    type Query {
      noop: String
    }

    type WriteValuePayload {
      value: String
      lazyValue: String
      error: String
    }

    type Subscription {
      onWriteValue(value: String): WriteValuePayload
    }
  |)

  class SourceResolver < GraphQL::BreadthExec::FieldResolver
    attr_reader :resolve_calls
    attr_reader :subscribe_calls

    def initialize(subscribe: nil, resolve: nil)
      @subscribe = subscribe
      @resolve = resolve
      @subscribe_calls = []
      @resolve_calls = []
    end

    def subscribe(exec_field, ctx)
      @subscribe_calls << [exec_field.arguments, ctx[:test_context]]
      return @subscribe.call(exec_field, ctx) if @subscribe

      exec_field.objects.first.fetch("events")
    end

    def resolve(exec_field, ctx)
      @resolve_calls << [exec_field.objects, ctx[:test_context]]
      return @resolve.call(exec_field, ctx) if @resolve

      exec_field.map_objects(&:itself)
    end
  end

  class EventErrorResolver < GraphQL::BreadthExec::FieldResolver
    def resolve(exec_field, _ctx)
      exec_field.resolve_all(GraphQL::ExecutionError.new("Event failed"))
    end
  end

  def test_perform_still_reports_unsupported_subscription_operation
    document = %|subscription { onWriteValue { value } }|

    expected = {
      "errors" => [{
        "message" => "Unsupported operation type",
        "path" => ["subscription"],
      }],
    }

    assert_equal expected, subscription_executor(document).perform
  end

  def test_subscribe_rejects_non_subscription_operations
    result = subscription_executor(%|{ noop }|).subscribe

    assert_equal(
      [{
        "message" => "Expected subscription operation",
        "path" => ["query"],
      }],
      result["errors"],
    )
  end

  def test_subscribe_reports_schema_without_subscription_root
    executor = GraphQL::BreadthExec::Executor.new(
      SCHEMA,
      GraphQL.parse(%|subscription { onWriteValue { value } }|),
      resolvers: BREADTH_RESOLVERS,
      root_object: { "events" => [] },
    )

    result = executor.subscribe

    assert_equal(
      [{
        "message" => "Schema is not configured to execute subscription operation",
        "path" => ["subscription"],
      }],
      result["errors"],
    )
  end

  def test_subscribe_reports_unknown_subscription_field
    result = subscription_executor(%|subscription { missing { value } }|).subscribe

    assert_equal "No field named 'missing' on 'Subscription'", result.dig("errors", 0, "message")
    assert_equal [{ "line" => 1, "column" => 16 }], result.dig("errors", 0, "locations")
  end

  def test_subscribe_reports_graphql_execution_error_from_source_resolver
    resolver = SourceResolver.new(subscribe: ->(_exec_field, _ctx) { raise GraphQL::ExecutionError, "Cannot subscribe" })

    result = subscription_executor(%|subscription { onWriteValue { value } }|, source_resolver: resolver).subscribe

    assert_equal "Cannot subscribe", result.dig("errors", 0, "message")
    assert_equal ["onWriteValue"], result.dig("errors", 0, "path")
  end

  def test_subscribe_reports_non_enumerable_source
    resolver = SourceResolver.new(subscribe: ->(_exec_field, _ctx) { Object.new })

    result = subscription_executor(%|subscription { onWriteValue { value } }|, source_resolver: resolver).subscribe

    assert_equal "Subscription source must return an Enumerable", result.dig("errors", 0, "message")
    assert_equal ["onWriteValue"], result.dig("errors", 0, "path")
  end

  def test_subscribe_reports_lazy_source_setup
    resolver = SourceResolver.new(subscribe: ->(_exec_field, _ctx) { GraphQL::BreadthExec::ExecutionPromise.new })

    result = subscription_executor(%|subscription { onWriteValue { value } }|, source_resolver: resolver).subscribe

    assert_equal "Subscription source setup does not support lazy promises", result.dig("errors", 0, "message")
    assert_equal ["onWriteValue"], result.dig("errors", 0, "path")
  end

  def test_stream_yields_one_result_for_one_source_event
    stream = subscription_executor(
      %|subscription { onWriteValue { value } }|,
      root_object: { "events" => [{ "value" => "first" }] },
    ).subscribe

    assert_instance_of GraphQL::BreadthExec::SubscriptionResponseStream, stream
    assert_equal(
      [{ "data" => { "onWriteValue" => { "value" => "first" } } }],
      stream.to_a,
    )
  end

  def test_stream_preserves_multiple_event_order
    stream = subscription_executor(
      %|subscription { onWriteValue { value } }|,
      root_object: {
        "events" => [
          { "value" => "first" },
          { "value" => "second" },
          { "value" => "third" },
        ],
      },
    ).subscribe

    assert_equal(
      [
        { "data" => { "onWriteValue" => { "value" => "first" } } },
        { "data" => { "onWriteValue" => { "value" => "second" } } },
        { "data" => { "onWriteValue" => { "value" => "third" } } },
      ],
      stream.to_a,
    )
  end

  def test_event_execution_uses_subscription_root_resolver
    resolver = SourceResolver.new(
      resolve: ->(exec_field, _ctx) { exec_field.map_objects { _1.fetch("payload") } },
    )

    stream = subscription_executor(
      %|subscription { onWriteValue { value } }|,
      source_resolver: resolver,
      root_object: { "events" => [{ "payload" => { "value" => "from resolver" } }] },
      context: { test_context: "ctx" },
    ).subscribe

    assert_equal [{ "data" => { "onWriteValue" => { "value" => "from resolver" } } }], stream.to_a
    assert_equal [[{}, "ctx"]], resolver.subscribe_calls
    assert_equal [[[{ "payload" => { "value" => "from resolver" } }], "ctx"]], resolver.resolve_calls
  end

  def test_event_execution_supports_lazy_fields
    stream = subscription_executor(
      %|subscription { onWriteValue { lazyValue } }|,
      root_object: { "events" => [{ "lazyValue" => "loaded" }] },
    ).subscribe

    assert_equal(
      [{ "data" => { "onWriteValue" => { "lazyValue" => "loaded" } } }],
      stream.to_a,
    )
  end

  def test_event_execution_errors_are_returned_in_result
    stream = subscription_executor(
      %|subscription { onWriteValue { error } }|,
      root_object: { "events" => [{ "value" => "bad" }] },
    ).subscribe

    assert_equal(
      [{
        "errors" => [{
          "message" => "Event failed",
          "locations" => [{ "line" => 1, "column" => 31 }],
          "path" => ["onWriteValue", "error"],
        }],
        "data" => { "onWriteValue" => { "error" => nil } },
      }],
      stream.to_a,
    )
  end

  def test_source_stream_errors_propagate_to_consumer
    source_stream = Enumerator.new do |yielder|
      yielder << { "value" => "before error" }
      raise RuntimeError, "source failed"
    end

    stream = subscription_executor(
      %|subscription { onWriteValue { value } }|,
      root_object: { "events" => source_stream },
    ).subscribe

    responses = []
    error = assert_raises(RuntimeError) do
      stream.each { responses << _1 }
    end

    assert_equal "source failed", error.message
    assert_equal [{ "data" => { "onWriteValue" => { "value" => "before error" } } }], responses
  end

  def test_controller_hooks_can_create_map_and_execute_events
    executor = subscription_executor(
      %|subscription { onWriteValue { value } }|,
      root_object: { "events" => [{ "value" => "from source" }] },
    )

    source_stream = executor.create_source_event_stream
    assert_equal [{ "value" => "from source" }], source_stream

    response_stream = executor.map_source_to_response_event(source_stream)
    assert_equal(
      [{ "data" => { "onWriteValue" => { "value" => "from source" } } }],
      response_stream.to_a,
    )

    assert_equal(
      { "data" => { "onWriteValue" => { "value" => "direct" } } },
      executor.execute_subscription_event({ "value" => "direct" }),
    )
  end

  def test_subscribe_cannot_be_called_twice
    executor = subscription_executor(%|subscription { onWriteValue { value } }|)

    executor.subscribe

    error = assert_raises(GraphQL::BreadthExec::ImplementationError) { executor.subscribe }
    assert_equal "Cannot subscribe more than once", error.message
  end

  def test_perform_cannot_be_called_after_subscribe
    executor = subscription_executor(%|subscription { onWriteValue { value } }|)

    executor.subscribe

    error = assert_raises(GraphQL::BreadthExec::ImplementationError) { executor.perform }
    assert_equal "Cannot perform after subscribe", error.message
  end

  def test_subscribe_cannot_be_called_after_perform
    executor = subscription_executor(%|{ noop }|)

    executor.perform

    error = assert_raises(GraphQL::BreadthExec::ImplementationError) { executor.subscribe }
    assert_equal "Cannot subscribe after perform", error.message
  end

  private

  def subscription_executor(document, source_resolver: SourceResolver.new, root_object: { "events" => [] }, context: {})
    GraphQL::BreadthExec::Executor.new(
      SUBSCRIPTION_SCHEMA,
      GraphQL.parse(document),
      resolvers: subscription_resolvers(source_resolver),
      root_object: root_object,
      context: context,
    )
  end

  def subscription_resolvers(source_resolver)
    {
      "Query" => {
        "noop" => GraphQL::BreadthExec::ValueResolver.new("noop"),
      },
      "Subscription" => {
        "onWriteValue" => source_resolver,
      },
      "WriteValuePayload" => {
        "value" => GraphQL::BreadthExec::HashKeyResolver.new("value"),
        "lazyValue" => DeferredHashResolver.new("lazyValue"),
        "error" => EventErrorResolver.new,
      },
    }.freeze
  end
end
