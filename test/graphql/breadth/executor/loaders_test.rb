# frozen_string_literal: true

require "test_helper"

class GraphQL::Breadth::Executor::LoadersTest < Minitest::Test

  class FancyLoader < GraphQL::Breadth::LazyLoader
    class << self
      attr_accessor :perform_keys
    end

    self.perform_keys = []

    def initialize(group:)
      super()
      @group = group
    end

    def map?
      true
    end

    def perform_map(keys, _ctx)
      self.class.perform_keys << keys.dup
      keys.map { |key| "#{key}-#{@group}" }
    end
  end

  class ConcurrentLoader < GraphQL::Breadth::LazyLoader
    class << self
      attr_accessor :active, :max_active, :events

      def reset_tracking!
        self.active = 0
        self.max_active = 0
        self.events = []
      end
    end

    concurrency limit: 2
    reset_tracking!

    def initialize(group:)
      super()
      @group = group
    end

    def map?
      true
    end

    def perform_map(keys, _ctx)
      self.class.events << [:start, @group, keys.dup]
      self.class.active += 1
      self.class.max_active = [self.class.max_active, self.class.active].max
      sleep 0.01
      keys.map { |key| "#{key}-#{@group}" }
    ensure
      self.class.events << [:finish, @group]
      self.class.active -= 1
    end
  end

  class LimitedConcurrentLoader < ConcurrentLoader
    concurrency limit: 1, resource: :limited_concurrent_loader
    reset_tracking!
  end

  class BoomConcurrentLoader < GraphQL::Breadth::LazyLoader
    concurrency limit: 2

    def map?
      true
    end

    def perform_map(_keys, _ctx)
      sleep 0
      raise GraphQL::ExecutionError, "async loader boom"
    end
  end

  class ChainedConcurrentLoader < GraphQL::Breadth::LazyLoader
    class << self
      attr_accessor :events

      def reset_tracking!
        self.events = []
      end
    end

    concurrency limit: 3
    reset_tracking!

    def initialize(group:, delay:)
      super()
      @group = group
      @delay = delay
    end

    def map?
      true
    end

    def perform_map(keys, _ctx)
      self.class.events << [:start, @group]
      sleep @delay
      keys.map { |key| "#{key}-#{@group}" }
    ensure
      self.class.events << [:finish, @group]
    end
  end

  class FirstResolver < GraphQL::Breadth::FieldResolver
    def resolve(exec_field, _ctx)
      exec_field.lazy(loader_class: FancyLoader, args: { group: "a" }, keys: exec_field.objects.map { _1["first"] })
    end
  end

  class SecondResolver < GraphQL::Breadth::FieldResolver
    def resolve(exec_field, _ctx)
      exec_field.lazy(loader_class: FancyLoader, args: { group: "a" }, keys: exec_field.objects.map { _1["second"] })
    end
  end

  class ThirdResolver < GraphQL::Breadth::FieldResolver
    def resolve(exec_field, _ctx)
      exec_field.lazy(loader_class: FancyLoader, args: { group: "b" }, keys: exec_field.objects.map { _1["third"] }).then do |values|
        values
      end
    end
  end

  class EagerValuesResolver < GraphQL::Breadth::FieldResolver
    def resolve(exec_field, _ctx)
      exec_field.lazy(
        loader_class: FancyLoader,
        args: { group: "a" },
        keys: exec_field.objects.map { _1["first"] },
        eager_values: { "Apple" => "Apple-cached" },
      )
    end
  end

  class FieldPreloadResolver < GraphQL::Breadth::FieldResolver
    def plan(exec_field, _ctx)
      exec_field.on_preload do
        exec_field.preload(
          FancyLoader,
          args: { group: "field" },
          keys: exec_field.objects.map { _1["first"] },
        ).then do |values|
          exec_field.attributes[:preloaded_values] = values
        end
      end
    end

    def resolve(exec_field, _ctx)
      exec_field.attributes[:preloaded_values]
    end
  end

  class ScopePreloadResolver < GraphQL::Breadth::FieldResolver
    def plan(exec_field, _ctx)
      exec_scope = exec_field.scope
      exec_scope.on_preload do
        exec_scope.preload(
          FancyLoader,
          args: { group: "scope" },
          keys: exec_scope.objects.map { _1["first"] },
        ).then do |values|
          exec_scope.attributes[:preloaded_values] = values
        end
      end
    end

    def resolve(exec_field, _ctx)
      exec_field.scope.attributes[:preloaded_values]
    end
  end

  class LoaderResolver < GraphQL::Breadth::FieldResolver
    def initialize(loader_class:, key:, group: nil)
      super()
      @loader_class = loader_class
      @key = key
      @group = group
    end

    def resolve(exec_field, _ctx)
      args = @group ? { group: @group } : nil
      exec_field.lazy(
        loader_class: @loader_class,
        args: args,
        keys: exec_field.objects.map { _1[@key] },
      )
    end
  end

  class ChainedLoaderResolver < GraphQL::Breadth::FieldResolver
    def initialize(key:)
      super()
      @key = key
    end

    def resolve(exec_field, _ctx)
      exec_field
        .lazy(
          loader_class: ChainedConcurrentLoader,
          args: { group: "fast", delay: 0.001 },
          keys: exec_field.objects.map { _1[@key] },
        )
        .then do |values|
          exec_field.lazy(
            loader_class: ChainedConcurrentLoader,
            args: { group: "chain", delay: 0.001 },
            keys: values,
          )
        end
    end
  end

  class SlowChainedLoaderResolver < GraphQL::Breadth::FieldResolver
    def resolve(exec_field, _ctx)
      exec_field.lazy(
        loader_class: ChainedConcurrentLoader,
        args: { group: "slow", delay: 0.05 },
        keys: exec_field.objects.map { _1["second"] },
      )
    end
  end

  LOADER_SCHEMA = GraphQL::Schema.from_definition(%|
    type Widget {
      first: String
      second: String
      third: String
      syncObject: Widget
      syncScalar: String
    }

    type Query {
      widget: Widget
    }
  |)

  LOADER_RESOLVERS = {
    "Widget" => {
      "first" => FirstResolver.new,
      "second" => SecondResolver.new,
      "third" => ThirdResolver.new,
      "syncObject" => GraphQL::Breadth::HashKeyResolver.new("syncObject"),
      "syncScalar" => GraphQL::Breadth::HashKeyResolver.new("syncScalar"),
    },
    "Query" => {
      "widget" => GraphQL::Breadth::HashKeyResolver.new("widget"),
    },
  }.freeze

  def setup
    FancyLoader.perform_keys = []
    ConcurrentLoader.reset_tracking!
    LimitedConcurrentLoader.reset_tracking!
    ChainedConcurrentLoader.reset_tracking!
  end

  def test_splits_loaders_by_group_across_fields
    document = GraphQL.parse(%|{
      widget {
        first
        second
        third
      }
    }|)

    source = {
      "widget" => {
        "first" => "Apple",
        "second" => "Banana",
        "third" => "Coconut",
      },
    }

    expected = {
      "data" => {
        "widget" => {
          "first" => "Apple-a",
          "second" => "Banana-a",
          "third" => "Coconut-b"
        }
      }
    }

    executor = GraphQL::Breadth::Executor.new(LOADER_SCHEMA, document, resolvers: LOADER_RESOLVERS, root_object: source)
    assert_equal expected, executor.result
    assert_equal [["Apple", "Banana"], ["Coconut"]], FancyLoader.perform_keys
  end

  def test_sync_lazy_loaders_do_not_enter_async_scheduler
    document = GraphQL.parse(%|{
      widget {
        first
        second
      }
    }|)

    source = {
      "widget" => {
        "first" => "Apple",
        "second" => "Banana",
      },
    }

    expected = {
      "data" => {
        "widget" => {
          "first" => "Apple-a",
          "second" => "Banana-a",
        },
      },
    }

    executor_class = Class.new(GraphQL::Breadth::Executor) do
      private

      def execute_concurrency_loader_jobs(*)
        raise "Async scheduler should not run for sync lazy loaders"
      end
    end

    executor = executor_class.new(LOADER_SCHEMA, document, resolvers: LOADER_RESOLVERS, root_object: source)
    assert_equal expected, executor.result
  end

  def test_concurrency_loaders_overlap_when_opted_in
    document = GraphQL.parse(%|{
      widget {
        first
        second
      }
    }|)

    source = {
      "widget" => {
        "first" => "Apple",
        "second" => "Banana",
      },
    }

    resolvers = LOADER_RESOLVERS.merge(
      "Widget" => LOADER_RESOLVERS["Widget"].merge(
        "first" => LoaderResolver.new(loader_class: ConcurrentLoader, key: "first", group: "a"),
        "second" => LoaderResolver.new(loader_class: ConcurrentLoader, key: "second", group: "b"),
      ),
    )

    expected = {
      "data" => {
        "widget" => {
          "first" => "Apple-a",
          "second" => "Banana-b",
        },
      },
    }

    executor = GraphQL::Breadth::Executor.new(LOADER_SCHEMA, document, resolvers: resolvers, root_object: source)
    assert_equal expected, executor.result
    assert_equal 2, ConcurrentLoader.max_active
  end

  def test_concurrency_loaders_respect_resource_limits
    document = GraphQL.parse(%|{
      widget {
        first
        second
      }
    }|)

    source = {
      "widget" => {
        "first" => "Apple",
        "second" => "Banana",
      },
    }

    resolvers = LOADER_RESOLVERS.merge(
      "Widget" => LOADER_RESOLVERS["Widget"].merge(
        "first" => LoaderResolver.new(loader_class: LimitedConcurrentLoader, key: "first", group: "a"),
        "second" => LoaderResolver.new(loader_class: LimitedConcurrentLoader, key: "second", group: "b"),
      ),
    )

    expected = {
      "data" => {
        "widget" => {
          "first" => "Apple-a",
          "second" => "Banana-b",
        },
      },
    }

    executor = GraphQL::Breadth::Executor.new(LOADER_SCHEMA, document, resolvers: resolvers, root_object: source)
    assert_equal expected, executor.result
    assert_equal 1, LimitedConcurrentLoader.max_active
  end

  def test_concurrency_loader_errors_are_applied_to_field_results
    document = GraphQL.parse(%|{
      widget {
        first
      }
    }|)

    source = {
      "widget" => {
        "first" => "Apple",
      },
    }

    resolvers = LOADER_RESOLVERS.merge(
      "Widget" => LOADER_RESOLVERS["Widget"].merge(
        "first" => LoaderResolver.new(loader_class: BoomConcurrentLoader, key: "first"),
      ),
    )

    executor = GraphQL::Breadth::Executor.new(LOADER_SCHEMA, document, resolvers: resolvers, root_object: source)
    result = executor.result

    assert_equal({ "widget" => { "first" => nil } }, result["data"])
    assert_equal "async loader boom", result.dig("errors", 0, "message")
    assert_equal ["widget", "first"], result.dig("errors", 0, "path")
  end

  def test_concurrency_chains_are_scheduled_while_slow_sibling_loader_is_running
    document = GraphQL.parse(%|{
      widget {
        first
        second
      }
    }|)

    source = {
      "widget" => {
        "first" => "Apple",
        "second" => "Banana",
      },
    }

    resolvers = LOADER_RESOLVERS.merge(
      "Widget" => LOADER_RESOLVERS["Widget"].merge(
        "first" => ChainedLoaderResolver.new(key: "first"),
        "second" => SlowChainedLoaderResolver.new,
      ),
    )

    expected = {
      "data" => {
        "widget" => {
          "first" => "Apple-fast-chain",
          "second" => "Banana-slow",
        },
      },
    }

    executor = GraphQL::Breadth::Executor.new(LOADER_SCHEMA, document, resolvers: resolvers, root_object: source)
    assert_equal expected, executor.result

    events = ChainedConcurrentLoader.events
    assert_operator events.index([:start, "chain"]), :<, events.index([:finish, "slow"])
  end

  def test_maintains_ordered_selections_around_object_fields
    document = GraphQL.parse(%|{
      widget {
        a: syncObject { first }
        first
        b: syncObject { first }
        second
      }
    }|)

    source = {
      "widget" => {
        "first" => "Apple",
        "second" => "Banana",
        "syncObject" => { "first" => "NotLazy" },
      },
    }

    expected = {
      "data" => {
        "widget" => {
          "a" => { "first" => "NotLazy-a" },
          "first" => "Apple-a",
          "b" => { "first" => "NotLazy-a" },
          "second" => "Banana-a",
        }
      }
    }

    executor = GraphQL::Breadth::Executor.new(LOADER_SCHEMA, document, resolvers: LOADER_RESOLVERS, root_object: source)
    result = executor.result
    assert_equal expected, result
    assert_equal result.dig("data", "widget").keys, expected.dig("data", "widget").keys
  end

  def test_maintains_ordered_selections_around_leaf_fields
    document = GraphQL.parse(%|{
      widget {
        a: syncScalar
        first
        b: syncScalar
        second
      }
    }|)

    source = {
      "widget" => {
        "first" => "Apple",
        "second" => "Banana",
        "syncScalar" => "NotLazy",
      },
    }

    expected = {
      "data" => {
        "widget" => {
          "a" => "NotLazy",
          "first" => "Apple-a",
          "b" => "NotLazy",
          "second" => "Banana-a",
        }
      }
    }

    executor = GraphQL::Breadth::Executor.new(LOADER_SCHEMA, document, resolvers: LOADER_RESOLVERS, root_object: source)
    result = executor.result
    assert_equal expected, result
    assert_equal result.dig("data", "widget").keys, expected.dig("data", "widget").keys
  end

  def test_lazy_field_uses_eager_values_without_loading_them
    document = GraphQL.parse(%|{
      widget {
        first
        second
      }
    }|)

    source = {
      "widget" => {
        "first" => "Apple",
        "second" => "Banana",
      },
    }

    resolvers = LOADER_RESOLVERS.merge(
      "Widget" => LOADER_RESOLVERS["Widget"].merge("first" => EagerValuesResolver.new),
    )

    expected = {
      "data" => {
        "widget" => {
          "first" => "Apple-cached",
          "second" => "Banana-a",
        }
      }
    }

    executor = GraphQL::Breadth::Executor.new(LOADER_SCHEMA, document, resolvers: resolvers, root_object: source)
    assert_equal expected, executor.result
    assert_equal [["Banana"]], FancyLoader.perform_keys
  end

  def test_resumes_field_execution_after_lazy_preloads
    document = GraphQL.parse(%|{
      widget {
        first
      }
    }|)

    source = {
      "widget" => {
        "first" => "Apple",
      },
    }

    resolvers = LOADER_RESOLVERS.merge(
      "Widget" => LOADER_RESOLVERS["Widget"].merge("first" => FieldPreloadResolver.new),
    )

    expected = {
      "data" => {
        "widget" => {
          "first" => "Apple-field",
        }
      }
    }

    executor = GraphQL::Breadth::Executor.new(LOADER_SCHEMA, document, resolvers: resolvers, root_object: source)
    assert_equal expected, executor.result
    assert_equal [["Apple"]], FancyLoader.perform_keys
  end

  def test_resumes_scope_execution_after_lazy_preloads
    document = GraphQL.parse(%|{
      widget {
        first
        second
      }
    }|)

    source = {
      "widget" => {
        "first" => "Apple",
        "second" => "Banana",
      },
    }

    resolvers = LOADER_RESOLVERS.merge(
      "Widget" => LOADER_RESOLVERS["Widget"].merge("first" => ScopePreloadResolver.new),
    )

    expected = {
      "data" => {
        "widget" => {
          "first" => "Apple-scope",
          "second" => "Banana-a",
        }
      }
    }

    executor = GraphQL::Breadth::Executor.new(LOADER_SCHEMA, document, resolvers: resolvers, root_object: source)
    assert_equal expected, executor.result
    assert_equal [["Apple"], ["Banana"]], FancyLoader.perform_keys
  end
end
