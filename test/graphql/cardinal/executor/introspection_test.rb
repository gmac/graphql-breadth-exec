# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::Executor::IntrospectionTest < Minitest::Test
  TEST_SCHEMA = GraphQL::Schema.from_definition(%|
    """@stitch description"""
    directive @stitch(key: ID!) repeatable on FIELD_DEFINITION

    """Status description"""
    enum Status {
      YES
      NO
      """maybe description"""
      MAYBE @deprecated(reason: "use no")
    }

    """Node description"""
    interface Node {
      id: ID!
    }

    """Widget description"""
    type Widget implements Node {
      id: ID!
      status: Status!
    }

    """Sprocket description"""
    type Sprocket implements Node {
      id: ID!
      status: Status!
    }

    """Trinket description"""
    union Trinket = Widget \| Sprocket

    type Query {
      node: Node! @stitch(key: "id")
      """widget description"""
      widget(id: ID!): Widget! @deprecated(reason: "use widgets")
      widgets(ids: [ID!]!): [Widget]!
      sprockets(ids: [ID!]!): [Sprocket]!
    }

    """TrinketInput description"""
    input TrinketInput {
      status: Status!
      state: String @deprecated(reason: "use status")
    }
    type Mutation {
      makeTrinkets(
        trinket: TrinketInput!
        """input description"""
        input: TrinketInput @deprecated(reason: "use trinket")
      ): [Trinket!]!
    }
  |)

  TEST_SCHEMA.get_type("String").specified_by_url("https://string.test")

  TEST_RESOLVERS = {
    **GraphQL::Cardinal::Introspection::TYPE_RESOLVERS,
    "Query" => {
      **GraphQL::Cardinal::Introspection::ENTRYPOINT_RESOLVERS,
    }
  }.freeze

  def test_introspect_schema_root_types
    result = execute_query(%|{
      __schema {
        queryType { name }
        mutationType { name }
        subscriptionType { name }
      }
    }|)

    expected = {
      "data" => {
        "__schema" => {
          "queryType" => { "name" => "Query" },
          "mutationType" => { "name" => "Mutation" },
          "subscriptionType" => nil,
        }
      }
    }

    assert_equal expected, result
  end

  def test_introspect_all_schema_types
    result = execute_query(%|{
      __schema {
        types {
          description
          fields { name }
          interfaces { name }
          kind { name }
          name
          ofType { name }
          possibleTypes { name }
        }
      }
    }|)

    expected = [
      "Boolean",
      "ID",
      "Mutation",
      "Node",
      "Query",
      "Sprocket",
      "Status",
      "String",
      "Trinket",
      "TrinketInput",
      "Widget",
      "__Directive",
      "__DirectiveLocation",
      "__EnumValue",
      "__Field",
      "__InputValue",
      "__Schema",
      "__Type",
      "__TypeKind",
    ]

    assert_equal expected, result.dig("data", "__schema", "types").map { _1["name"] }.sort
  end

  def test_introspect_all_schema_directives
    result = execute_query(%|{
      __schema {
        directives {
          args { name }
          description
          isRepeatable
          locations
          name
        }
      }
    }|)

    expected = ["deprecated", "include", "oneOf", "skip", "specifiedBy", "stitch"]
    assert_equal expected, result.dig("data", "__schema", "directives").map { _1["name"] }.sort
  end

  def test_introspect_directive_type
    result = execute_query(%|{
      __schema {
        directives {
          args { name }
          description
          isRepeatable
          locations
          name
        }
      }
    }|)

    expected = {
      "args" => [{ "name" => "key" }],
      "description" => "@stitch description",
      "isRepeatable" => true,
      "locations" => [:FIELD_DEFINITION],
      "name" => "stitch"
    }

    assert_equal expected, result.dig("data", "__schema", "directives").find { _1["name"] == "stitch" }
  end

  def test_introspect_type_access
    result = execute_query(%|{
      __type(name: "Widget") { 
        description
        kind
        name
      }
    }|)

    expected = {
      "data" => {
        "__type" => {
          "description" => "Widget description",
          "kind" => "OBJECT",
          "name" => "Widget",
        },
      },
    }

    assert_equal expected, result
  end

  def test_introspect_type_fields
    result = execute_query(%|{
      has_fields: __type(name: "Query") {
        some: fields { name }
        all: fields(includeDeprecated: true) { name }
      }
      no_fields: __type(name: "Trinket") {
        fields { name }
      }
    }|)

    expected_some = ["node", "sprockets", "widgets"]
    expected_all = ["node", "sprockets", "widget", "widgets"]

    assert_equal expected_some, result.dig("data", "has_fields", "some").map { _1["name"] }.sort
    assert_equal expected_all, result.dig("data", "has_fields", "all").map { _1["name"] }.sort
    assert_nil result.dig("data", "no_fields", "fields")
  end

  def test_introspect_type_enum_values
    result = execute_query(%|{
      is_enum: __type(name: "Status") {
        some: enumValues { name }
        all: enumValues(includeDeprecated: true) { name }
      }
      non_enum: __type(name: "Widget") {
        enumValues { name }
      }
    }|)

    expected_some = ["NO", "YES"]
    expected_all = ["MAYBE", "NO", "YES"]

    assert_equal expected_some, result.dig("data", "is_enum", "some").map { _1["name"] }.sort
    assert_equal expected_all, result.dig("data", "is_enum", "all").map { _1["name"] }.sort
    assert_nil result.dig("data", "non_enum", "enumValues")
  end

  def test_introspect_type_input_fields
    result = execute_query(%|{
      is_input: __type(name: "TrinketInput") {
        some: inputFields { name }
        all: inputFields(includeDeprecated: true) { name }
      }
      non_input: __type(name: "Widget") {
        inputFields { name }
      }
    }|)

    expected_some = ["status"]
    expected_all = ["state", "status"]

    assert_equal expected_some, result.dig("data", "is_input", "some").map { _1["name"] }.sort
    assert_equal expected_all, result.dig("data", "is_input", "all").map { _1["name"] }.sort
    assert_nil result.dig("data", "non_input", "inputFields")
  end

  def test_introspect_type_interfaces
    result = execute_query(%|{
      has_interfaces: __type(name: "Widget") {
        interfaces { name }
      }
      no_interfaces: __type(name: "Trinket") {
        interfaces { name }
      }
    }|)

    assert_equal [{ "name" => "Node" }], result.dig("data", "has_interfaces", "interfaces")
    assert_nil result.dig("data", "no_interfaces", "interfaces")
  end

  def test_introspect_type_possible_types
    result = execute_query(%|{
      is_abstract: __type(name: "Trinket") {
        possibleTypes { name }
      }
      not_abstract: __type(name: "Widget") {
        possibleTypes { name }
      }
    }|)

    expected = ["Sprocket", "Widget"]
    assert_equal expected, result.dig("data", "is_abstract", "possibleTypes").map { _1["name"] }.sort
    assert_nil result.dig("data", "not_abstract", "possibleTypes")
  end

  def test_introspect_type_specified_by_url
    result = execute_query(%|{
      scalar: __type(name: "String") { 
        specifiedByURL
      }
      non_scalar: __type(name: "Widget") { 
        specifiedByURL
      }
    }|)

    expected = {
      "data" => {
        "scalar" => {
          "specifiedByURL" => "https://string.test",
        },
        "non_scalar" => {
          "specifiedByURL" => nil,
        },
      },
    }

    assert_equal expected, result
  end

  def test_introspect_type_kind_of_type
    result = execute_query(%|{
      __type(name: "Mutation") { 
        name
        kind
        ofType { name }
        fields {
          type {
            name
            kind
            ofType {
              name
              kind
              ofType {
                name
                kind
                ofType {
                  name
                  kind
                }
              }
            }
          }
        }
      }
    }|)

    expected = {
      "data" => {
        "__type" => {
          "name" => "Mutation",
          "kind" => "OBJECT",
          "ofType" => nil,
          "fields" => [{
            "type" => {
              "name" => nil,
              "kind" => "NON_NULL",
              "ofType" => {
                "name" => nil,
                "kind" => "LIST",
                "ofType" => {
                  "name" => nil,
                  "kind" => "NON_NULL",
                  "ofType" => {
                    "name" => "Trinket",
                    "kind" => "UNION",
                  },
                },
              },
            },
          }]
        },
      },
    }

    assert_equal expected, result
  end

  def test_introspect_enum_value
    result = execute_query(%|{
      __type(name: "Status") { 
        enumValues(includeDeprecated: true) {
          deprecationReason
          description
          isDeprecated
          name
        }
      }
    }|)

    expected = {
      "data" => {
        "__type" => {
          "enumValues" => [{
            "deprecationReason" => nil,
            "description" => nil,
            "isDeprecated" => false,
            "name" => "YES",
          }, {
            "deprecationReason" => nil,
            "description" => nil,
            "isDeprecated" => false,
            "name" => "NO",
          }, {
            "deprecationReason" => "use no",
            "description" => "maybe description",
            "isDeprecated" => true,
            "name" => "MAYBE",
          }],
        },
      },
    }

    assert_equal expected, result
  end

  def test_introspect_field
    result = execute_query(%|{
      __type(name: "Query") { 
        fields(includeDeprecated: true) {
          args { name }
          deprecationReason
          description
          isDeprecated
          name
          type { kind }
        }
      }
    }|)

    expected = {
      "data" => {
        "__type" => {
          "fields" => [{
            "args" => [],
            "deprecationReason" => nil,
            "description" => nil,
            "isDeprecated" => false,
            "name" => "node",
            "type" => { "kind" => "NON_NULL" },
          }, {
            "args" => [{ "name" => "id" }],
            "deprecationReason" => "use widgets",
            "description" => "widget description",
            "isDeprecated" => true,
            "name" => "widget",
            "type" => { "kind" => "NON_NULL" },
          }, {
            "args" => [{ "name" => "ids" }],
            "deprecationReason" => nil,
            "description" => nil,
            "isDeprecated" => false,
            "name" => "widgets",
            "type" => { "kind" => "NON_NULL" },
          }, {
            "args" => [{ "name" => "ids" }],
            "deprecationReason" => nil,
            "description" => nil,
            "isDeprecated" => false,
            "name" => "sprockets",
            "type" => { "kind" => "NON_NULL" },
          }]
        }
      }
    }

    assert_equal expected, result
  end

  def test_introspect_arguments
    result = execute_query(%|{
      __type(name: "Mutation") { 
        fields {
          some: args { name }
          all: args(includeDeprecated: true) {
            deprecationReason
            description
            isDeprecated
            name
            type { kind }
          }
        }
      }
    }|)

    expected = {
      "some" => [{ "name" => "trinket" }],
      "all" => [{
        "deprecationReason" => nil,
        "description" => nil,
        "isDeprecated" => false,
        "name" => "trinket",
        "type" => { "kind" => "NON_NULL" },
      }, {
        "deprecationReason" => "use trinket",
        "description" => "input description",
        "isDeprecated" => true,
        "name" => "input",
        "type" => { "kind" => "INPUT_OBJECT" },
      }],
    }
    assert_equal expected, result.dig("data", "__type", "fields", 0)
  end

  def test_introspect_argument_default_values
    schema = GraphQL::Schema.from_definition(%|
      enum TestEnum {
        A
        B
      }
      input TestInput {
        a: TestEnum!
        b: String
        c: [String]
      }
      type Query {
        test1(input: TestEnum = A): Boolean
        test2(input: [TestEnum] = [A, B]): Boolean
        test3(input: TestInput = { a: A, b: "sfoo", c: ["sfoo"] }): Boolean
        test4(input: [TestInput] = [{ a: A }]): Boolean
        test5(input: String = "sfoo"): Boolean
        test6(input: Int = 23): Boolean
        test7(input: Float = 23.77): Boolean
        test8(input: Boolean = true): Boolean
        test9(input: Boolean = null): Boolean
      }
    |)

    result = execute_query(%|{
      __type(name: "Query") { 
        fields {
          args { defaultValue }
        }
      }
    }|, schema: schema)

    expected_values = [
      "A",
      "[A, B]",
      %|{a: A, b: "sfoo", c: ["sfoo"]}|,
      "[{a: A}]",
      %|"sfoo"|,
      "23",
      "23.77",
      "true",
      "null",
    ]

    expected_values.each_with_index do |value, i|
      assert_equal value, result.dig("data", "__type", "fields", i, "args", 0, "defaultValue"), "Mismatch with ##{i}"
    end
  end

  private

  def execute_query(document, schema: TEST_SCHEMA)
    GraphQL::Cardinal::Executor.new(schema, TEST_RESOLVERS, GraphQL.parse(document), {}).perform
  end
end
