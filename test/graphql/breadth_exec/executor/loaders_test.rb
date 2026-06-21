# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::LoadersTest < Minitest::Test

  class FancyLoader < GraphQL::BreadthExec::LazyLoader
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

  class FirstResolver < GraphQL::BreadthExec::FieldResolver
    def resolve(exec_field, _ctx)
      exec_field.lazy(loader_class: FancyLoader, args: { group: "a" }, keys: exec_field.objects.map { _1["first"] })
    end
  end

  class SecondResolver < GraphQL::BreadthExec::FieldResolver
    def resolve(exec_field, _ctx)
      exec_field.lazy(loader_class: FancyLoader, args: { group: "a" }, keys: exec_field.objects.map { _1["second"] })
    end
  end

  class ThirdResolver < GraphQL::BreadthExec::FieldResolver
    def resolve(exec_field, _ctx)
      exec_field.lazy(loader_class: FancyLoader, args: { group: "b" }, keys: exec_field.objects.map { _1["third"] }).then do |values|
        values
      end
    end
  end

  class EagerValuesResolver < GraphQL::BreadthExec::FieldResolver
    def resolve(exec_field, _ctx)
      exec_field.lazy(
        loader_class: FancyLoader,
        args: { group: "a" },
        keys: exec_field.objects.map { _1["first"] },
        eager_values: { "Apple" => "Apple-cached" },
      )
    end
  end

  class FieldPreloadResolver < GraphQL::BreadthExec::FieldResolver
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

  class ScopePreloadResolver < GraphQL::BreadthExec::FieldResolver
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
      "syncObject" => GraphQL::BreadthExec::HashKeyResolver.new("syncObject"),
      "syncScalar" => GraphQL::BreadthExec::HashKeyResolver.new("syncScalar"),
    },
    "Query" => {
      "widget" => GraphQL::BreadthExec::HashKeyResolver.new("widget"),
    },
  }.freeze

  def setup
    FancyLoader.perform_keys = []
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

    executor = GraphQL::BreadthExec::Executor.new(LOADER_SCHEMA, document, resolvers: LOADER_RESOLVERS, root_object: source)
    assert_equal expected, executor.result
    assert_equal [["Apple", "Banana"], ["Coconut"]], FancyLoader.perform_keys
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

    executor = GraphQL::BreadthExec::Executor.new(LOADER_SCHEMA, document, resolvers: LOADER_RESOLVERS, root_object: source)
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

    executor = GraphQL::BreadthExec::Executor.new(LOADER_SCHEMA, document, resolvers: LOADER_RESOLVERS, root_object: source)
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

    executor = GraphQL::BreadthExec::Executor.new(LOADER_SCHEMA, document, resolvers: resolvers, root_object: source)
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

    executor = GraphQL::BreadthExec::Executor.new(LOADER_SCHEMA, document, resolvers: resolvers, root_object: source)
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

    executor = GraphQL::BreadthExec::Executor.new(LOADER_SCHEMA, document, resolvers: resolvers, root_object: source)
    assert_equal expected, executor.result
    assert_equal [["Apple"], ["Banana"]], FancyLoader.perform_keys
  end
end
