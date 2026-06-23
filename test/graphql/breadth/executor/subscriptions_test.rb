# frozen_string_literal: true

require "timeout"

require "test_helper"

class GraphQL::Breadth::Executor::SubscriptionsTest < Minitest::Test
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

  class SourceResolver < GraphQL::Breadth::FieldResolver
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

  class EventErrorResolver < GraphQL::Breadth::FieldResolver
    def resolve(exec_field, _ctx)
      exec_field.resolve_all(GraphQL::ExecutionError.new("Event failed"))
    end
  end

  def test_result_raises_for_subscription_operation
    error = assert_raises(GraphQL::Breadth::ImplementationError) do
      subscription_executor(%|subscription { onWriteValue { value } }|).result
    end

    assert_equal "Use subscribe for subscription operations", error.message
  end

  def test_incremental_result_raises_for_subscription_operation
    error = assert_raises(GraphQL::Breadth::ImplementationError) do
      subscription_executor(%|subscription { onWriteValue { value } }|).incremental_result
    end

    assert_equal "Use subscribe for subscription operations", error.message
  end

  def test_subscribe_raises_for_query_operation
    error = assert_raises(GraphQL::Breadth::ImplementationError) do
      subscription_executor(%|{ noop }|).subscribe
    end

    assert_equal "Only allowed for subscription operations", error.message
  end

  def test_subscribe_returns_subscription_response_stream_for_subscription_operation
    result = subscription_executor(
      %|subscription { onWriteValue { value } }|,
      root_object: { "events" => [{ "value" => "direct" }] },
    ).subscribe

    assert_instance_of GraphQL::Breadth::SubscriptionResponseStream, result
    assert_equal [{ "data" => { "onWriteValue" => { "value" => "direct" } } }], result.to_a
  end

  def test_subscribe_reports_graphql_execution_error_from_source_resolver
    resolver = SourceResolver.new(subscribe: ->(_exec_field, _ctx) { raise GraphQL::ExecutionError, "Cannot subscribe" })

    result = subscription_executor(%|subscription { onWriteValue { value } }|, source_resolver: resolver).subscribe

    assert_equal "Cannot subscribe", result.dig("errors", 0, "message")
    assert_equal ["onWriteValue"], result.dig("errors", 0, "path")
  end

  def test_subscribe_raises_for_plain_field_resolver_without_subscription_hook
    error = assert_raises(NotImplementedError) do
      subscription_executor(
        %|subscription { onWriteValue { value } }|,
        source_resolver: GraphQL::Breadth::SelfResolver.new,
      ).subscribe
    end

    assert_equal "FieldResolver#subscribe must be implemented.", error.message
  end

  def test_subscribe_raises_for_non_enumerable_source
    resolver = SourceResolver.new(subscribe: ->(_exec_field, _ctx) { Object.new })

    error = assert_raises(GraphQL::Breadth::ImplementationError) do
      subscription_executor(%|subscription { onWriteValue { value } }|, source_resolver: resolver).subscribe
    end

    assert_equal "Subscription source must return an Enumerable", error.message
  end

  def test_subscribe_raises_for_lazy_source_setup
    resolver = SourceResolver.new(subscribe: ->(_exec_field, _ctx) { GraphQL::Breadth::Executor::ExecutionPromise.new })

    error = assert_raises(GraphQL::Breadth::ImplementationError) do
      subscription_executor(%|subscription { onWriteValue { value } }|, source_resolver: resolver).subscribe
    end

    assert_equal "Subscription source must return an Enumerable", error.message
  end

  def test_stream_yields_one_result_for_one_source_event
    stream = subscription_executor(
      %|subscription { onWriteValue { value } }|,
      root_object: { "events" => [{ "value" => "first" }] },
    ).subscribe

    assert_instance_of GraphQL::Breadth::SubscriptionResponseStream, stream
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

  def test_stream_yields_events_published_after_subscription_result_is_created
    events = Queue.new
    source_stream = Enumerator.new do |yielder|
      loop do
        event = events.pop
        break if event == :done

        yielder << event
      end
    end

    stream = subscription_executor(
      %|subscription { onWriteValue { value } }|,
      root_object: { "events" => source_stream },
    ).subscribe

    deliveries = Queue.new
    stream_errors = Queue.new
    consumer = Thread.new do
      stream.each { deliveries << _1 }
    rescue StandardError => e
      stream_errors << e
    end

    assert_equal(
      { "data" => { "onWriteValue" => { "value" => "after subscribe" } } },
      begin
        events << { "value" => "after subscribe" }
        Timeout.timeout(1) { deliveries.pop }
      end,
    )

    assert_equal(
      { "data" => { "onWriteValue" => { "value" => "after that" } } },
      begin
        events << { "value" => "after that" }
        Timeout.timeout(1) { deliveries.pop }
      end,
    )

    events << :done
    assert consumer.join(1), "Expected subscription stream consumer to finish"
    flunk("Expected no stream errors, got #{stream_errors.pop.message}") unless stream_errors.empty?
  ensure
    consumer&.kill
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

  def test_subscribe_returns_same_stream_when_called_twice
    executor = subscription_executor(%|subscription { onWriteValue { value } }|)

    stream = executor.subscribe

    assert_same stream, executor.subscribe
  end

  def test_result_raises_after_subscription_response_stream_was_created
    executor = subscription_executor(%|subscription { onWriteValue { value } }|)

    executor.subscribe
    error = assert_raises(GraphQL::Breadth::ImplementationError) { executor.result }

    assert_equal "Use subscribe for subscription operations", error.message
  end

  private

  def subscription_executor(document, source_resolver: SourceResolver.new, root_object: { "events" => [] }, context: {})
    GraphQL::Breadth::Executor.new(
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
        "noop" => GraphQL::Breadth::ValueResolver.new("noop"),
      },
      "Subscription" => {
        "onWriteValue" => source_resolver,
      },
      "WriteValuePayload" => {
        "value" => GraphQL::Breadth::HashKeyResolver.new("value"),
        "lazyValue" => DeferredHashResolver.new("lazyValue"),
        "error" => EventErrorResolver.new,
      },
    }.freeze
  end
end
