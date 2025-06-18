# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::Executor::ScopeLoaderTest < Minitest::Test

  class FancyLoader < GraphQL::Cardinal::Loader
    class << self
      attr_accessor :perform_keys
    end

    self.perform_keys = []

    def perform(keys)
      self.class.perform_keys << keys.dup
      keys.map { |key| "#{key}-#{group}" }
    end
  end

  class FirstResolver < GraphQL::Cardinal::FieldResolver
    def resolve(objects, _args, _ctx, scope)
      scope.defer(FancyLoader, group: "a", keys: objects.map { _1["first"] })
    end
  end

  class SecondResolver < GraphQL::Cardinal::FieldResolver
    def resolve(objects, _args, _ctx, scope)
      scope.defer(FancyLoader, group: "a", keys: objects.map { _1["second"] })
    end
  end

  class ThirdResolver < GraphQL::Cardinal::FieldResolver
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
    },
    "Query" => {
      "widget" => GraphQL::Cardinal::HashKeyResolver.new("widget"),
    },
  }.freeze

  def setup
    FancyLoader.perform_keys = []
  end

  def test_runs
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

    executor = GraphQL::Cardinal::BreadthExecutor.new(LOADER_SCHEMA, LOADER_RESOLVERS, document, source)
    assert_equal expected, executor.perform
    assert_equal [["Apple", "Banana"], ["Coconut"]], FancyLoader.perform_keys
  end
end
