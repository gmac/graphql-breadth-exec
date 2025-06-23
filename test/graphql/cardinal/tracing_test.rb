# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::TracingTest < Minitest::Test
  GRAPHQL_GEM_SCHEMA = GraphQL::Schema.from_definition(SDL, default_resolve: GEM_RESOLVERS)

  module GemTrace
    def execute_field(field:, query:, ast_node:, arguments:, object:)
      puts "Execute gem field #{field.name}"
      super
    end
  end

  GRAPHQL_GEM_SCHEMA.trace_with(GemTrace)

  class CardinalTracer < GraphQL::Cardinal::Tracer
    def before_resolve_field(parent_type, field_name, sources_count, context)
      puts "Execute cardinal field #{field_name} #{sources_count}"
      super
    end
  end

  def setup
    @data = sized_data(10)
  end

  def test_graphql_gem_tracing
    GRAPHQL_GEM_SCHEMA.execute(document: GraphQL.parse(BASIC_DOCUMENT), root_value: @data).to_h
  end

  def test_cardinal_gem_tracing
    GraphQL::Cardinal::Executor.new(
      SCHEMA,
      BREADTH_RESOLVERS,
      GraphQL.parse(BASIC_DOCUMENT),
      @data,
      tracers: [CardinalTracer.new],
    ).perform
  end

  private

  def sized_data(size = 10)
    products = (1..size).map do |i|
      {
        "id" => i.to_s,
        "title" => "Product #{i}",
        "variants" => {
          "nodes" => (1..5).map do |j|
            {
              "id" => "#{i}-#{j}",
              "title" => "Variant #{j}"
            }
          end
        }
      }
    end

    {
      "products" => {
        "nodes" => products
      }
    }
  end
end
