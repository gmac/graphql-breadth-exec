# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::Executor::PlaygroundTest < Minitest::Test
  include GraphQL::Cardinal::Executor::Coercions

  GRAPHQL_GEM_SCHEMA = GraphQL::Schema.from_definition(SDL, default_resolve: GEM_RESOLVERS)

  def test_nullable_positional_error_adds_path
    document = %|mutation($input: WidgetCreateInput = { price: 30 })  {
      widgetCreate(input: { price: 7 }) { status }
    }|

    query = GraphQL::Query.new(SCHEMA, document)
    operation = query.selected_operation
    puts type_from_ast(query, operation.variables.first.type).to_type_signature
    vars = coerce_variable_values(query, operation.variables, {})
    puts vars

    field = query.get_field(SCHEMA.mutation, "widgetCreate")
    node = operation.selections.first
    
    puts get_argument_values(query, field, node, vars)
    #result = coerce_variables(query, { "input" => ["sfoo"] })

    # source = {
    #   "widgetCreate" => [
    #     { "status" => "YES" },
    #   ],
    # }

    # #result = GRAPHQL_GEM_SCHEMA.execute(document: GraphQL.parse(document), root_value: source)
    # #pp result.to_h
    # assert_equal source, breadth_exec(document, source, variables: {}).dig("data")
    assert true
  end
end
