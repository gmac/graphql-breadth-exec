# frozen_string_literal: true

require "test_helper"

class GraphQL::Breadth::Executor::ExecutionFieldTest < Minitest::Test
  TEST_SCHEMA = GraphQL::Schema.from_definition(%|
    input Input { name: String }

    type Query {
      nullable: String
      required: String!
      nullableList: [String]
      requiredItems: [String!]
      requiredListAndItems: [String!]!
      nestedNullableList: [[String!]]!
      nestedRequiredList: [[String!]!]!
      withArgs(name: String, input: [Input], tags: [String], missing: String): String
    }
  |)

  def test_path_uses_response_key_and_schema_path_uses_schema_name
    exec_field = build_field('{ aliasName: nullable }')

    assert_equal ["aliasName"], exec_field.path
    assert_equal ["nullable"], exec_field.schema_path
  end

  def test_scope_path_and_schema_path_are_empty_at_root
    exec_field = build_field("{ nullable }")

    assert_equal [], exec_field.scope.path
    assert_equal [], exec_field.scope.schema_path
  end

  def test_propagates_null_when_type_is_entirely_non_null
    refute_predicate build_field("{ nullable }"), :propagates_null?
    assert_predicate build_field("{ required }"), :propagates_null?
    refute_predicate build_field("{ nullableList }"), :propagates_null?
    refute_predicate build_field("{ requiredItems }"), :propagates_null?
    assert_predicate build_field("{ requiredListAndItems }"), :propagates_null?
    refute_predicate build_field("{ nestedNullableList }"), :propagates_null?
    assert_predicate build_field("{ nestedRequiredList }"), :propagates_null?
  end

  def test_builds_arguments_from_literals_and_variables
    exec_field = build_field(
      'query($name: String!) { withArgs(name: $name, input: { name: "nested" }, tags: ["a", null]) }',
      variables: { "name" => "Ada" },
    )

    assert_equal(
      {
        name: "Ada",
        input: [{ name: "nested" }],
        tags: ["a", nil],
      },
      exec_field.arguments,
    )
  end

  def test_resolve_all_maps_graphql_execution_error_to_object_set
    exec_field = build_field("{ nullable }", objects: [{}, {}])

    result = exec_field.resolve_all(GraphQL::ExecutionError.new("Whoops"))

    assert_equal 2, result.size
    assert result.all? { _1.equal?(result.first) }
    assert_instance_of GraphQL::Breadth::ExecutionError, result.first
    assert_equal exec_field, result.first.exec_field
    assert_nil result.first.path
  end

  def test_map_objects_with_index_yields_object_and_index
    exec_field = build_field("{ nullable }", objects: [
      { "value" => "first" },
      { "value" => "second" },
      { "value" => "third" },
    ])

    result = exec_field.map_objects_with_index { |object, index| "#{index}:#{object["value"]}" }

    assert_equal ["0:first", "1:second", "2:third"], result
  end

  def test_field_and_scope_attributes_api
    exec_field = build_field("{ nullable }")
    exec_scope = exec_field.scope

    refute exec_field.attribute?(:cached)
    assert_equal "fallback", exec_field.attribute(:cached, default: "fallback")
    exec_field.attributes[:cached] = "field-value"
    assert exec_field.attribute?(:cached)
    assert_equal "field-value", exec_field.attribute(:cached)

    refute exec_scope.attribute?(:cached)
    assert_equal "fallback", exec_scope.attribute(:cached, default: "fallback")
    exec_scope.attributes[:cached] = "scope-value"
    assert exec_scope.attribute?(:cached)
    assert_equal "scope-value", exec_scope.attribute(:cached)
  end

  private

  def build_field(document_string, variables: {}, objects: [{}])
    document = GraphQL.parse(document_string)
    executor = GraphQL::Breadth::Executor.new(TEST_SCHEMA, document, variables: variables)
    operation = executor.query.selected_operation
    executor.input.coerce_variable_values(operation.variables, executor.query.provided_variables || {})
    node = operation.selections.first
    parent_type = executor.query.root_type_for_operation(operation.operation_type)
    exec_scope = GraphQL::Breadth::Executor::ExecutionScope.new(
      executor: executor,
      parent_type: parent_type,
      selections: operation.selections,
      objects: objects,
      results: Array.new(objects.length) { {} },
    )

    definition = executor.query.get_field(parent_type, node.name)
    GraphQL::Breadth::Executor::ExecutionField.new(
      node.alias || node.name,
      nodes: [node],
      scope: exec_scope,
      definition: definition,
      resolver: GraphQL::Breadth::HashKeyResolver.new(node.name),
    )
  end
end
