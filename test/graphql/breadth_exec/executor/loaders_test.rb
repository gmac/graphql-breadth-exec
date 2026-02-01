# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::LoadersTest < Minitest::Test

  class FancyLoader < GraphQL::BreadthExec::Loader
    class << self
      attr_accessor :perform_keys
    end

    self.perform_keys = []

    def perform(keys)
      self.class.perform_keys << keys.dup
      keys.map { |key| "#{key}-#{group}" }
    end
  end

  class FirstResolver < GraphQL::BreadthExec::FieldResolver
    def resolve(objects, _args, _ctx, scope)
      scope.defer(FancyLoader, group: "a", keys: objects.map { _1["first"] })
    end
  end

  class SecondResolver < GraphQL::BreadthExec::FieldResolver
    def resolve(objects, _args, _ctx, scope)
      scope.defer(FancyLoader, group: "a", keys: objects.map { _1["second"] })
    end
  end

  class ThirdResolver < GraphQL::BreadthExec::FieldResolver
    def resolve(objects, _args, _ctx, scope)
      scope.defer(FancyLoader, group: "b", keys: objects.map { _1["third"] }).then do |values|
        values
      end
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

    executor = GraphQL::BreadthExec::Executor.new(LOADER_SCHEMA, LOADER_RESOLVERS, document, source)
    assert_equal expected, executor.perform
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

    executor = GraphQL::BreadthExec::Executor.new(LOADER_SCHEMA, LOADER_RESOLVERS, document, source)
    result = executor.perform
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

    executor = GraphQL::BreadthExec::Executor.new(LOADER_SCHEMA, LOADER_RESOLVERS, document, source)
    result = executor.perform
    assert_equal expected, result
    assert_equal result.dig("data", "widget").keys, expected.dig("data", "widget").keys
  end
end
