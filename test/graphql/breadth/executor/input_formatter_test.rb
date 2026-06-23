# typed: true
# frozen_string_literal: true

require "test_helper"

module GraphQL
  module Breadth
    class Executor
      class InputFormatterTest < Minitest::Test
        UNDEFINED = GraphQL::Breadth::Executor::UNDEFINED

        TEST_SCHEMA = GraphQL::Schema.from_definition(%|
          enum TestStatus {
            ACTIVE
            INACTIVE
          }

          input NestedInput {
            value: String
            nested: NestedInput
          }

          input TestInput {
            string: String
            int: Int
            float: Float
            boolean: Boolean
            id: ID
            enum: TestStatus
            nested: NestedInput
            stringList: [String]
            nonNullItemList: [String!]
            nestedList: [NestedInput]
          }

          input RequiredFieldsInput {
            required: String!
            optional: String
          }

          input ValidatedFieldsInput {
            scalar: String
            list: [String]
            input: ValidatedFieldsInput
            inputList: [ValidatedFieldsInput]
          }

          input OneOfInput @oneOf {
            string: String
            int: Int
          }

          scalar ErrorScalar

          type Mutation {
            testInput(input: TestInput): Boolean
            requiredFields(input: RequiredFieldsInput!): Boolean
            argWithDefault(input: String = "fallback-value"): Boolean
            oneOf(input: OneOfInput!): Boolean
            validates(input: ValidatedFieldsInput!): Boolean
            validatesOneArg(a: String, b: String): Boolean
            testErrorScalar(input: ErrorScalar): Boolean
            validatesWithDefault(input: String = "a"): Boolean
          }

          type Query {
            ping: Boolean
          }
        |)

        TEST_SCHEMA.get_type("ErrorScalar").singleton_class.prepend(Module.new do
          def coerce_input(_input, _context)
            raise GraphQL::ExecutionError.new("Custom coercion failure", extensions: { "code" => "CUSTOM_ERROR" })
          end
        end)

        TEST_SCHEMA.mutation.fields["validatesOneArg"].tap do |f|
          f.validates(required: { one_of: [:a, :b] })
        end

        TEST_SCHEMA.get_type("ValidatedFieldsInput").tap do |t|
          t.arguments["scalar"].validates(length: { minimum: 2 })
          t.arguments["list"].validates(length: { minimum: 2 })
        end

        TEST_SCHEMA.mutation.fields["validatesWithDefault"].arguments["input"].validates(length: { minimum: 2 })

        def setup
          @context = GraphQL::Query.new(TEST_SCHEMA, "{ __typename }").context
          @input = GraphQL::Breadth::Executor::InputFormatter.new(@context)
          @state = GraphQL::Breadth::Executor::InputFormatter::State.new
        end

        # === type_from_ast ===

        def test_type_from_ast_named_type
          type_string = "String"
          result = @input.type_from_ast(get_type_node(type_string))

          assert_equal(GraphQL::Types::String, result)
          assert_equal(type_string, result.to_type_signature)
        end

        def test_type_from_ast_non_null_type
          type_string = "String!"
          result = @input.type_from_ast(get_type_node(type_string))

          assert_predicate(result, :non_null?)
          assert_equal(GraphQL::Types::String, result.of_type)
          assert_equal(type_string, result.to_type_signature)
        end

        def test_type_from_ast_list_type
          type_string = "[String]"
          result = @input.type_from_ast(get_type_node(type_string))

          assert_predicate(result, :list?)
          assert_equal(GraphQL::Types::String, result.of_type)
          assert_equal(type_string, result.to_type_signature)
        end

        def test_type_from_ast_non_null_list_type
          type_string = "[String]!"
          result = @input.type_from_ast(get_type_node(type_string))

          assert_predicate(result, :non_null?)
          assert_predicate(result.of_type, :list?)
          assert_equal(GraphQL::Types::String, result.of_type.of_type)
          assert_equal(type_string, result.to_type_signature)
        end

        def test_type_from_ast_list_of_non_null_type
          type_string = "[String!]"
          result = @input.type_from_ast(get_type_node(type_string))

          assert_predicate(result, :list?)
          assert_predicate(result.of_type, :non_null?)
          assert_equal(GraphQL::Types::String, result.of_type.of_type)
          assert_equal(type_string, result.to_type_signature)
        end

        def test_type_from_ast_non_null_list_of_non_null_type
          type_string = "[String!]!"
          result = @input.type_from_ast(get_type_node(type_string))

          assert_predicate(result, :non_null?)
          assert_predicate(result.of_type, :list?)
          assert_predicate(result.of_type.of_type, :non_null?)
          assert_equal(GraphQL::Types::String, result.of_type.of_type.of_type)
          assert_equal(type_string, result.to_type_signature)
        end

        def test_type_from_ast_nested_list_type
          type_string = "[[Int]]"
          result = @input.type_from_ast(get_type_node(type_string))

          assert_predicate(result, :list?)
          assert_predicate(result.of_type, :list?)
          assert_equal(GraphQL::Types::Int, result.of_type.of_type)
          assert_equal(type_string, result.to_type_signature)
        end

        def test_type_from_ast_unknown_type_returns_nil
          assert_nil @input.type_from_ast(get_type_node("UnknownType"))
        end

        # === coerce_variable_values ===

        def test_coerce_variable_values_empty_inputs_returns_empty
          var_defs = get_variables_ast("")
          result = @input.coerce_variable_values(var_defs, {})

          assert_equal({}, result)
        end

        def test_coerce_variable_values_non_input_type_raises_error
          var_defs = get_variables_ast("$value: Query")

          error = assert_raises(GraphQL::Breadth::InputValidationErrorSet) do
            @input.coerce_variable_values(var_defs, { "value" => {} })
          end

          assert_equal(1, error.errors.size)
          assert_equal("Query isn't a valid input type (on $value)", error.errors.first&.message)
        end

        def test_coerce_variable_values_unknown_type_raises_error
          var_defs = get_variables_ast("$value: UnknownType!")

          error = assert_raises(GraphQL::Breadth::InputValidationErrorSet) do
            @input.coerce_variable_values(var_defs, { "value" => "anything" })
          end

          assert_equal(1, error.errors.size)
          assert_match(/UnknownType isn't a valid input type/, error.errors.first&.message)
        end

        def test_coerce_variable_values_with_valid_variable
          var_defs = get_variables_ast("$name: String")
          result = @input.coerce_variable_values(var_defs, { "name" => "hello" })

          assert_equal({ "name" => "hello" }, result)
        end

        def test_coerce_variable_values_always_keeps_root_variable_names_as_natural_string_keys
          var_defs = get_variables_ast("$my_fancyVar: TestInput")
          vars_input = { "my_fancyVar" => { "stringList" => ["a", "b"] } }

          @input.symbolize_keys = true
          result = @input.coerce_variable_values(var_defs, vars_input)
          assert_equal({ "my_fancyVar" => { string_list: ["a", "b"] } }, result)

          @input.symbolize_keys = false
          result = @input.coerce_variable_values(var_defs, vars_input)
          assert_equal({ "my_fancyVar" => { "stringList" => ["a", "b"] } }, result)
        end

        def test_coerce_variable_values_applies_default_when_not_provided
          var_defs = get_variables_ast('$name: String = "default"')
          result = @input.coerce_variable_values(var_defs, {})

          assert_equal({ "name" => "default" }, result)
        end

        def test_coerce_variable_values_raises_error_when_non_null_isnt_provided
          var_defs = get_variables_ast("$name: String!")

          error = assert_raises(GraphQL::Breadth::InputValidationErrorSet) do
            @input.coerce_variable_values(var_defs, {})
          end

          assert_equal(1, error.errors.size)
          assert_equal('Variable "$name" of required type "String!" was not provided.', error.errors.first&.message)
        end

        def test_coerce_variable_values_raises_error_when_non_null_provided_as_null
          var_defs = get_variables_ast("$name: String!")

          error = assert_raises(GraphQL::Breadth::InputValidationErrorSet) do
            @input.coerce_variable_values(var_defs, { "name" => nil })
          end

          assert_equal(1, error.errors.size)
          assert_equal('Variable "$name" of non-null type "String!" must not be null.', error.errors.first&.message)
        end

        def test_coerce_variable_values_nullable_variable_with_no_value_is_unset
          var_defs = get_variables_ast("$name: String")
          result = @input.coerce_variable_values(var_defs, {})

          assert_equal({}, result)
        end

        def test_coerce_variable_values_nullable_variable_with_null_value_is_null
          var_defs = get_variables_ast("$name: String")
          result = @input.coerce_variable_values(var_defs, { "name" => nil })

          assert_equal({ "name" => nil }, result)
        end

        def test_coerce_variable_values_invalid_value_raises_error
          var_defs = get_variables_ast("$count: Int")

          error = assert_raises(GraphQL::Breadth::InputValidationErrorSet) do
            @input.coerce_variable_values(var_defs, { "count" => "not-an-int" })
          end

          assert_equal(1, error.errors.size)
          assert_equal('Variable $count of type Int was provided invalid value', error.errors.first&.message)
        end

        def test_coerce_variable_values_formats_multiple_variables
          var_defs = get_variables_ast("$a: String!, $b: Int")
          result = @input.coerce_variable_values(var_defs, { "a" => "hello", "b" => 42 })

          assert_equal({ "a" => "hello", "b" => 42 }, result)
        end

        def test_coerce_variable_values_raises_error_for_list_of_non_null_containing_null
          var_defs = get_variables_ast("$input: [String!]")

          error = assert_raises(GraphQL::Breadth::InputValidationErrorSet) do
            @input.coerce_variable_values(var_defs, { "input" => ["A", nil, "B"] })
          end

          assert_equal(1, error.errors.size)
          assert_equal("Variable $input of type [String!] was provided invalid value for 1 (Non-null type cannot be null)", error.errors.first&.message)
        end

        def test_coerce_variable_values_raises_with_multiple_errors
          var_defs = get_variables_ast("$a: String!, $b: Int!")

          error = assert_raises(GraphQL::Breadth::InputValidationErrorSet) do
            @input.coerce_variable_values(var_defs, {})
          end

          assert_equal(2, error.errors.size)
        end

        def test_coerce_variable_values_stores_runtime_validation_errors_by_variable_name
          var_defs = get_variables_ast("$myVar: ValidatedFieldsInput")
          result = @input.coerce_variable_values(var_defs, { "myVar" => { "scalar" => "a" } })

          assert_equal({ "myVar" => { scalar: "a" } }, result)
          assert_equal(["myVar"], @input.variable_validator_errors.keys)
          assert_equal(["scalar is too short (minimum is 2)"], @input.variable_validator_errors["myVar"]&.map(&:message))
        end

        # === coerce_argument_values ===

        def test_coerce_argument_values_returns_empty_for_empty_args
          field_def = get_root_field("mutation", "testInput")
          field_node = get_field_node("testInput")
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({}, result)
          assert_empty(errors)
        end

        def test_coerce_argument_values_coerces_literal_string_value
          field_def = get_root_field("mutation", "testInput")
          field_node = get_field_node('testInput(input: { string: "hello" })')
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({ input: { string: "hello" } }, result)
          assert_empty(errors)
        end

        def test_coerce_argument_values_coerces_complex_input
          field_def = get_root_field("mutation", "testInput")
          field_node = get_field_node('testInput(input: { string: "foo", stringList: ["bar"], int: 42 })')
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({ input: { string: "foo", string_list: ["bar"], int: 42 } }, result)
          assert_empty(errors)
        end

        def test_coerce_argument_values_coerces_single_value_into_list
          field_def = get_root_field("mutation", "testInput")
          field_node = get_field_node('testInput(input: { stringList: "single" })')
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({ input: { string_list: ["single"] } }, result)
          assert_empty(errors)
        end

        def test_coerce_argument_values_preserves_null_values_in_list
          field_def = get_root_field("mutation", "testInput")
          field_node = get_field_node('testInput(input: { stringList: ["A", null, "C"] })')
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({ input: { string_list: ["A", nil, "C"] } }, result)
          assert_empty(errors)
        end

        def test_coerce_argument_values_invalidates_lists_with_invalid_items
          field_def = get_root_field("mutation", "testInput")
          field_node = get_field_node('testInput(input: { nonNullItemList: ["A", null, "C"] })')
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({}, result)
          assert_equal(1, errors.size)
          assert_equal("Expected value node to be non-null.", errors.first&.message)
        end

        def test_coerce_argument_values_uses_default_when_argument_not_provided
          field_def = get_root_field("mutation", "argWithDefault")
          field_node = get_field_node("argWithDefault")
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({ input: "fallback-value" }, result)
          assert_empty(errors)
        end

        def test_coerce_argument_values_returns_error_for_missing_non_null_argument
          field_def = get_root_field("mutation", "requiredFields")
          field_node = get_field_node("requiredFields")
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({}, result)
          assert_equal(1, errors.size)
          assert_equal('Argument "input" of required type "RequiredFieldsInput!" was not provided.', errors.first&.message)
        end

        def test_coerce_argument_values_uses_default_when_variable_not_provided
          field_def = get_root_field("mutation", "argWithDefault")
          field_node = get_field_node("argWithDefault(input: $myVar)")
          result, errors = @input.coerce_argument_values(field_def, field_node, variables: {})

          assert_equal({ input: "fallback-value" }, result)
          assert_empty(errors)
        end

        def test_coerce_argument_values_returns_error_for_missing_non_null_variable
          field_def = get_root_field("mutation", "requiredFields")
          field_node = get_field_node("requiredFields(input: $myVar)")
          result, errors = @input.coerce_argument_values(field_def, field_node, variables: {})

          assert_equal({}, result)
          assert_equal(1, errors.size)
          assert_equal('Argument "input" of required type "RequiredFieldsInput!" was provided the variable "$myVar" which was not provided a runtime value.', errors.first&.message)
        end

        def test_coerce_argument_values_returns_error_for_null_on_non_null_argument
          field_def = get_root_field("mutation", "requiredFields")
          field_node = get_field_node("requiredFields(input: null)")
          result, errors = @input.coerce_argument_values(field_def, field_node, variables: {})

          assert_equal({}, result)
          assert_equal(1, errors.size)
          assert_equal('Argument "input" of non-null type "RequiredFieldsInput!" must not be null.', errors.first&.message)
        end

        def test_coerce_argument_values_returns_error_for_null_variable_on_non_null_argument
          field_def = get_root_field("mutation", "requiredFields")
          field_node = get_field_node("requiredFields(input: $myVar)")
          result, errors = @input.coerce_argument_values(field_def, field_node, variables: { "myVar" => nil })

          assert_equal({}, result)
          assert_equal(1, errors.size)
          assert_equal('Argument "input" of non-null type "RequiredFieldsInput!" must not be null.', errors.first&.message)
        end

        def test_coerce_argument_values_returns_error_for_invalid_value
          field_def = get_root_field("mutation", "testInput")
          field_node = get_field_node('testInput(input: ["foo", "bar"])')
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({}, result)
          assert_equal(1, errors.size)
          assert_equal("Expected value node to be an input object.", errors.first&.message)
        end

        def test_coerce_argument_values_preserves_extensions_from_coerce_input_execution_error
          field_def = get_root_field("mutation", "testErrorScalar")
          field_node = get_field_node('testErrorScalar(input: "bad-value")')

          reported = assert_error_reported(InputValidationErrorSet) do
            result, errors = @input.coerce_argument_values(field_def, field_node)

            assert_equal({}, result)
            assert_equal(1, errors.size)
            assert_equal("Custom coercion failure", errors.first.message)
            assert_equal({ "code" => "CUSTOM_ERROR" }, errors.first.extensions)
          end #: as GraphQL::Breadth::InputValidationErrorSet

          assert_equal(1, reported.errors.size)
        end

        def test_coerce_argument_values_reports_error_for_coercion_errors
          field_def = get_root_field("mutation", "requiredFields")
          field_node = get_field_node('requiredFields(input: null)')

          reported = assert_error_reported(InputValidationErrorSet) do
            result, errors = @input.coerce_argument_values(field_def, field_node)

            assert_equal({}, result)
            assert_equal(1, errors.size)
            assert_instance_of(InputCoercionError, errors.first)
          end #: as GraphQL::Breadth::InputValidationErrorSet

          assert_equal(1, reported.errors.size)
          assert_equal('Argument "input" of non-null type "RequiredFieldsInput!" must not be null.', reported.message)
        end

        def test_coerce_argument_values_coerces_variable_value
          field_def = get_root_field("mutation", "testInput")
          field_node = get_field_node("testInput(input: $inputVar)")
          result, errors = @input.coerce_argument_values(field_def, field_node, variables: { "inputVar" => { string: "from-var" } })

          assert_equal({ input: { string: "from-var" } }, result)
          assert_empty(errors)
        end

        def test_coerce_argument_values_formats_keys_as_strings_when_symbolize_keys_disabled
          @input.symbolize_keys = false
          field_def = get_root_field("mutation", "testInput")
          field_node = get_field_node('testInput(input: { stringList: ["hello"], nested: { value: "deep" } })')
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({ "input" => { "stringList" => ["hello"], "nested" => { "value" => "deep" } } }, result)
          assert_empty(errors)
        end

        def test_coerce_argument_values_runs_validators_on_arguments
          field_def = get_root_field("mutation", "validates")
          field_node = get_field_node('validates(input: { scalar: "a" })')
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({ input: { scalar: "a" } }, result)
          assert_equal(1, errors.size)
          assert_equal("scalar is too short (minimum is 2)", errors.first&.message)
        end

        def test_coerce_argument_values_runs_validators_on_fields
          field_def = get_root_field("mutation", "validatesOneArg")
          field_node = get_field_node('validatesOneArg(a: "a", b: "b")')
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({ a: "a", b: "b" }, result)
          assert_equal(1, errors.size)
          assert_equal("validatesOneArg must include exactly one of the following arguments: a, b.", errors.first&.message)
        end

        def test_coerce_argument_values_returns_validator_errors_from_default_when_arg_not_provided
          field_def = get_root_field("mutation", "validatesWithDefault")
          field_node = get_field_node("validatesWithDefault")
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({ input: "a" }, result)
          assert_equal(1, errors.size)
          assert_instance_of(InputValidatorError, errors.first)
          assert_equal("input is too short (minimum is 2)", errors.first.message)
        end

        def test_coerce_argument_values_returns_validator_errors_from_default_when_variable_not_provided
          field_def = get_root_field("mutation", "validatesWithDefault")
          field_node = get_field_node("validatesWithDefault(input: $myVar)")
          result, errors = @input.coerce_argument_values(field_def, field_node, variables: {})

          assert_equal({ input: "a" }, result)
          assert_equal(1, errors.size)
          assert_instance_of(InputValidatorError, errors.first)
          assert_equal("input is too short (minimum is 2)", errors.first.message)
        end

        def test_coerce_argument_values_propagates_both_coercion_and_validator_errors_for_nested_input
          field_def = get_root_field("mutation", "validates")
          field_node = get_field_node('validates(input: { scalar: "a", input: "not-an-object" })')

          assert_error_reported(InputValidationErrorSet) do
            result, errors = @input.coerce_argument_values(field_def, field_node)

            assert_equal({}, result)
            assert_equal(2, errors.size)
            assert_instance_of(InputCoercionError, errors[0])
            assert_equal("Expected value node to be an input object.", errors[0].message)
            assert_instance_of(InputValidatorError, errors[1])
            assert_equal("scalar is too short (minimum is 2)", errors[1].message)
          end
        end

        def test_coerce_argument_values_preserves_variable_validator_error_extensions
          var_defs = get_variables_ast("$myVar: ValidatedFieldsInput")
          @input.coerce_variable_values(var_defs, { "myVar" => { "scalar" => "a" } })

          field_def = get_root_field("mutation", "validates")
          field_node = get_field_node("validates(input: $myVar)")
          result, errors = @input.coerce_argument_values(field_def, field_node, variables: @input.variables)

          assert_equal({ input: { scalar: "a" } }, result)
          assert_equal(1, errors.size)
          assert_instance_of(InputValidatorError, errors.first)
          assert_equal("scalar is too short (minimum is 2)", errors.first.message)
          assert_equal({ "code" => "INVALID_INPUT" }, errors.first.extensions)
        end

        def test_coerce_argument_values_includes_extensions_on_validator_errors
          field_def = get_root_field("mutation", "validates")
          field_node = get_field_node('validates(input: { scalar: "a" })')
          result, errors = @input.coerce_argument_values(field_def, field_node)

          assert_equal({ input: { scalar: "a" } }, result)
          assert_equal(1, errors.size)
          assert_instance_of(InputValidatorError, errors.first)
          assert_equal({ "code" => "INVALID_INPUT" }, errors.first.extensions)
        end

        # === coerce_input_value ===

        def test_coerce_input_value_coerces_valid_non_null_value
          type = get_type("String!")
          result = @input.coerce_input_value("hello", type, state: @state)

          assert_equal("hello", result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_for_null_on_non_null_type
          type = get_type("String!")
          result = @input.coerce_input_value(nil, type, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Non-null type cannot be null.", @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_returns_nil_for_null_on_nullable_type
          type = get_type("String")
          result = @input.coerce_input_value(nil, type, state: @state)

          assert_nil(result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_coerces_array_for_list_type
          type = get_type("[String]")
          result = @input.coerce_input_value(["a", "b", "c"], type, state: @state)

          assert_equal(["a", "b", "c"], result)
          assert_predicate(result, :frozen?)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_wraps_single_value_as_array_for_list_type
          type = get_type("[String]")
          result = @input.coerce_input_value("single", type, state: @state)

          assert_equal(["single"], result)
          assert_predicate(result, :frozen?)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_with_path_for_single_invalid_list_value
          type = get_type("[Int]")
          result = @input.coerce_input_value("not-an-int", type, state: @state)

          assert_equal([nil], result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal([0], @state.coercion_errors[0].path)
          assert_equal("Cannot represent non-Int value.", @state.coercion_errors[0].message)
        end

        def test_coerce_input_value_returns_nil_for_null_on_list_type
          type = get_type("[String]")
          result = @input.coerce_input_value(nil, type, state: @state)

          assert_nil(result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_at_index_for_invalid_list_item
          type = get_type("[Int]")
          result = @input.coerce_input_value([1, "not-an-int", 3], type, state: @state)

          assert_equal([1, nil, 3], result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal([1], @state.coercion_errors.first.path)
          assert_equal("Cannot represent non-Int value.", @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_adds_error_for_null_among_non_null_list_items
          type = get_type("[String!]")
          result = @input.coerce_input_value(["a", nil, "c"], type, state: @state)

          assert_equal(["a", UNDEFINED, "c"], result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal([1], @state.coercion_errors.first.path)
          assert_equal("Non-null type cannot be null.", @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_coerces_valid_array_for_non_null_list_type
          input = ["a", "b"]
          result1 = @input.coerce_input_value(input, get_type("[String]!"), state: @state)
          result2 = @input.coerce_input_value(input, get_type("[String!]!"), state: @state)

          assert_equal(input, result1)
          assert_equal(input, result2)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_for_missing_non_null_list_type
          type = get_type("[String]!")
          result = @input.coerce_input_value(nil, type, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Non-null type cannot be null.", @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_coerces_empty_list
          type = get_type("[String]")
          result = @input.coerce_input_value([], type, state: @state)

          assert_equal([], result)
          assert_empty(@state.coercion_errors)
          assert_predicate(result, :frozen?)
        end

        def test_coerce_input_value_coerces_valid_nested_list
          type = get_type("[[Int]]")
          result = @input.coerce_input_value([[1], [2, 3]], type, state: @state)

          assert_equal([[1], [2, 3]], result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_wraps_single_value_twice_for_nested_list
          type = get_type("[[Int]]")
          result = @input.coerce_input_value(42, type, state: @state)

          assert_equal([[42]], result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_wraps_each_item_for_nested_list
          type = get_type("[[Int]]")
          result = @input.coerce_input_value([1, 2, 3], type, state: @state)

          assert_equal([[1], [2], [3]], result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_preserves_null_values_in_nested_list
          type = get_type("[[Int]]")
          result = @input.coerce_input_value([42, [nil], nil], type, state: @state)

          assert_equal([[42], [nil], nil], result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_returns_nil_for_null_on_nested_list
          type = get_type("[[Int]]")
          result = @input.coerce_input_value(nil, type, state: @state)

          assert_nil(result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_coerces_list_of_input_objects
          type = get_type("[NestedInput]")
          result = @input.coerce_input_value([{ "value" => "a" }, { "value" => "b" }], type, state: @state)

          assert_equal([{ value: "a" }, { value: "b" }], result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_for_invalid_item_in_list_of_input_objects
          type = get_type("[NestedInput]")
          result = @input.coerce_input_value([{ "value" => "a" }, "not-an-object", { "value" => "c" }], type, state: @state)

          assert_equal([{ value: "a" }, UNDEFINED, { value: "c" }], result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal([1], @state.coercion_errors.first.path)
          assert_equal('Expected type "NestedInput" to be an object.', @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_adds_error_for_nested_field_in_list_of_input_objects
          type = get_type("[TestInput]")
          input = [
            { "int" => 1 },
            { "int" => "not-an-int" },
            { "int" => 3 },
          ]
          result = @input.coerce_input_value(input, type, state: @state)

          assert_equal([{ int: 1 }, { int: nil }, { int: 3 }], result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal([1, "int"], @state.coercion_errors.first.path)
          assert_equal("Cannot represent non-Int value.", @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_tracks_path_across_list_and_object_positions
          type = get_type("[TestInput]")
          input = [
            { "nestedList" => [{ "value" => "ok" }, { "value" => "also-ok" }] },
            { "nestedList" => [{ "value" => "fine" }, "not-an-object", { "value" => "still-fine" }] },
          ]
          result = @input.coerce_input_value(input, type, state: @state)

          assert_equal(
            [
              { nested_list: [{ value: "ok" }, { value: "also-ok" }] },
              { nested_list: [{ value: "fine" }, UNDEFINED, { value: "still-fine" }] },
            ],
            result,
          )
          assert_equal(1, @state.coercion_errors.size)
          assert_equal([1, "nestedList", 1], @state.coercion_errors.first.path)
          assert_equal('Expected type "NestedInput" to be an object.', @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_collects_errors_with_deeply_nested_paths
          type = get_type("[TestInput]")
          input = [
            { "nested" => { "badField" => "x" } },
            { "nestedList" => [{ "badField" => "y" }] },
            { "int" => "not-int", "boolean" => "not-bool" },
            { "nested" => { "nested" => { "badField" => "z" } } },
          ]
          result = @input.coerce_input_value(input, type, state: @state)

          assert_equal(4, result.size)
          assert_equal(5, @state.coercion_errors.size)

          assert_equal([0, "nested"], @state.coercion_errors[0].path)
          assert_equal('Field "badField" is not defined by type "NestedInput".', @state.coercion_errors[0].message)

          assert_equal([1, "nestedList", 0], @state.coercion_errors[1].path)
          assert_equal('Field "badField" is not defined by type "NestedInput".', @state.coercion_errors[1].message)

          assert_equal([2, "int"], @state.coercion_errors[2].path)
          assert_equal("Cannot represent non-Int value.", @state.coercion_errors[2].message)

          assert_equal([2, "boolean"], @state.coercion_errors[3].path)
          assert_equal("Cannot represent non-Boolean value.", @state.coercion_errors[3].message)

          assert_equal([3, "nested", "nested"], @state.coercion_errors[4].path)
          assert_equal('Field "badField" is not defined by type "NestedInput".', @state.coercion_errors[4].message)
        end

        def test_coerce_input_value_coerces_input_object_with_valid_fields
          type = get_type("TestInput")
          result = @input.coerce_input_value({ "string" => "hello", "int" => 42 }, type, state: @state)

          assert_equal({ string: "hello", int: 42 }, result)
          assert_predicate(result, :frozen?)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_formats_keys_as_strings_when_symbolize_keys_disabled
          @input.symbolize_keys = false
          type = get_type("TestInput")
          result = @input.coerce_input_value({ "stringList" => ["hello"] }, type, state: @state)

          assert_equal({ "stringList" => ["hello"] }, result)
          assert_predicate(result, :frozen?)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_uses_graphql_name_in_static_error_path
          type = get_type("TestInput")
          result = @input.coerce_input_value({ "nestedList" => [{ "unknown" => "x" }] }, type, state: @state)

          assert_equal({ nested_list: [{}] }, result)
          assert_equal(["nestedList", 0], @state.coercion_errors.first.path)
        end

        def test_coerce_input_value_adds_error_for_non_hash_input_object
          type = get_type("TestInput")
          result = @input.coerce_input_value("not-an-object", type, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal('Expected type "TestInput" to be an object.', @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_adds_error_for_missing_required_field
          type = get_type("RequiredFieldsInput")
          result = @input.coerce_input_value({ "optional" => "hello" }, type, state: @state)

          assert_equal({ optional: "hello" }, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal(["required"], @state.coercion_errors.first.path)
          assert_equal('Field "required" of required type "String!" was not provided.', @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_adds_error_for_unknown_field
          type = get_type("TestInput")
          result = @input.coerce_input_value({ "unknownField" => "value" }, type, state: @state)

          assert_equal({}, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal('Field "unknownField" is not defined by type "TestInput".', @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_coerces_nested_input_object
          type = get_type("TestInput")
          result = @input.coerce_input_value({ "nested" => { "value" => "hello" } }, type, state: @state)

          assert_equal({ nested: { value: "hello" } }, result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_for_nested_input_object_error
          type = get_type("TestInput")
          result = @input.coerce_input_value({ "nested" => "not-an-object" }, type, state: @state)

          assert_equal({ nested: UNDEFINED }, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal(["nested"], @state.coercion_errors.first.path)
          assert_equal('Expected type "NestedInput" to be an object.', @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_allows_one_of_with_single_field
          type = get_type("OneOfInput")
          result = @input.coerce_input_value({ "string" => "hello" }, type, state: @state)

          assert_equal({ string: "hello" }, result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_for_one_of_with_multiple_fields
          type = get_type("OneOfInput")
          result = @input.coerce_input_value({ "string" => "hello", "int" => 42 }, type, state: @state)

          assert_equal({ string: "hello", int: 42 }, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal('Exactly one key must be specified for OneOf type "OneOfInput".', @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_adds_error_for_one_of_with_null_value
          type = get_type("OneOfInput")
          result = @input.coerce_input_value({ "string" => nil }, type, state: @state)

          assert_equal({ string: nil }, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal('Exactly one value must be specified for OneOf type "OneOfInput", but "string" was null.', @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_adds_error_for_one_of_with_no_fields
          type = get_type("OneOfInput")
          result = @input.coerce_input_value({}, type, state: @state)

          assert_equal({}, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal('Exactly one key must be specified for OneOf type "OneOfInput".', @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_coerces_valid_string
          type = get_type("String")
          result = @input.coerce_input_value("hello", type, state: @state)

          assert_equal("hello", result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_for_invalid_string
          type = get_type("String")
          result = @input.coerce_input_value(true, type, state: @state)

          assert_nil(result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Cannot represent non-String value.", @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_coerces_valid_int
          type = get_type("Int")
          result = @input.coerce_input_value(42, type, state: @state)

          assert_equal(42, result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_for_invalid_int
          type = get_type("Int")
          result = @input.coerce_input_value("not-an-int", type, state: @state)

          assert_nil(result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Cannot represent non-Int value.", @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_coerces_valid_float
          type = get_type("Float")
          result = @input.coerce_input_value(3.14, type, state: @state)

          assert_in_delta(3.14, result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_coerces_valid_float_with_compatible_value
          type = get_type("Float")
          result = @input.coerce_input_value(42, type, state: @state)

          assert_in_delta(42.0, result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_for_invalid_float
          type = get_type("Float")
          result = @input.coerce_input_value("not-a-float", type, state: @state)

          assert_nil(result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Cannot represent non-Float value.", @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_coerces_valid_boolean
          type = get_type("Boolean")
          result = @input.coerce_input_value(true, type, state: @state)

          assert_equal(true, result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_for_invalid_boolean
          type = get_type("Boolean")
          result = @input.coerce_input_value("not-a-boolean", type, state: @state)

          assert_nil(result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Cannot represent non-Boolean value.", @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_coerces_valid_id
          type = get_type("ID")

          result1 = @input.coerce_input_value("abc123", type, state: @state)
          assert_equal("abc123", result1)
          assert_empty(@state.coercion_errors)

          result2 = @input.coerce_input_value(123, type, state: @state)
          assert_equal("123", result2)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_for_invalid_id
          type = get_type("ID")
          result = @input.coerce_input_value(true, type, state: @state)

          assert_nil(result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Cannot represent non-ID value.", @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_coerces_valid_enum
          type = get_type("TestStatus")
          result = @input.coerce_input_value("ACTIVE", type, state: @state)

          assert_equal("ACTIVE", result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_for_invalid_enum
          type = get_type("TestStatus")
          result = @input.coerce_input_value("INVALID", type, state: @state)

          assert_nil(result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Value does not exist in 'TestStatus' enum.", @state.coercion_errors.first&.message)
        end

        def test_coerce_input_value_enum_with_internal_value_mapping
          test_enum = Class.new(GraphQL::Schema::Enum) do
            graphql_name "MappedEnum"
            value "FOO", value: "InternalFoo"
            value "BAR", value: 123456789
          end

          foo_result = @input.coerce_input_value("FOO", test_enum, state: @state)
          assert_equal("InternalFoo", foo_result)
          assert_empty(@state.coercion_errors)

          bar_result = @input.coerce_input_value("BAR", test_enum, state: @state)
          assert_equal(123456789, bar_result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_for_scalar_coercion_error
          test_scalar = Class.new(GraphQL::Schema::Scalar) do
            graphql_name "ErrorScalar"

            class << self
              def coerce_input(input, _context)
                raise GraphQL::CoercionError, "Custom coercion error: #{input}"
              end
            end
          end

          result = @input.coerce_input_value("bad-value", test_scalar, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Custom coercion error: bad-value", @state.coercion_errors[0].message)
        end

        def test_coerce_input_value_preserves_extensions_from_execution_error
          test_scalar = Class.new(GraphQL::Schema::Scalar) do
            graphql_name "ExtErrorScalar"

            class << self
              def coerce_input(input, _context)
                raise GraphQL::ExecutionError.new("Custom coercion failure", extensions: { "code" => "CUSTOM_ERROR" })
              end
            end
          end

          result = @input.coerce_input_value("bad-value", test_scalar, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Custom coercion failure", @state.coercion_errors[0].message)
          assert_equal({ "code" => "CUSTOM_ERROR" }, @state.coercion_errors[0].extensions)
        end

        def test_coerce_input_value_returns_nil_for_custom_scalar_coerced_to_nil
          test_scalar = Class.new(GraphQL::Schema::Scalar) do
            graphql_name "NilScalar"

            class << self
              def coerce_input(_input, _context)
                nil
              end
            end
          end

          result = @input.coerce_input_value("any-value", test_scalar, state: @state)

          assert_nil(result)
          assert_empty(@state.coercion_errors)
        end

        def test_coerce_input_value_adds_error_for_custom_scalar_exception
          test_scalar = Class.new(GraphQL::Schema::Scalar) do
            graphql_name "BrokenScalar"

            class << self
              def coerce_input(_input, _context)
                raise StandardError, "Something went wrong"
              end
            end
          end

          result = @input.coerce_input_value("any-value", test_scalar, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal('Expected type "BrokenScalar".', @state.coercion_errors[0].message)
        end

        def test_coerce_input_value_collects_errors_for_multiple_invalid_fields
          type = get_type("TestInput")
          result = @input.coerce_input_value({ "int" => "not-int", "boolean" => "not-bool" }, type, state: @state)

          assert_equal({ int: nil, boolean: nil }, result)
          assert_equal(2, @state.coercion_errors.size)

          assert_equal("Cannot represent non-Int value.", @state.coercion_errors[0].message)
          assert_equal(["int"], @state.coercion_errors[0].path)

          assert_equal("Cannot represent non-Boolean value.", @state.coercion_errors[1].message)
          assert_equal(["boolean"], @state.coercion_errors[1].path)
        end

        # === coerce_input_value validation ===

        def test_coerce_input_value_passes_validation
          type = get_type("ValidatedFieldsInput")
          result = @input.coerce_input_value({ "scalar" => "ab" }, type, state: @state)

          assert_equal({ scalar: "ab" }, result)
          assert_empty(@state.coercion_errors)
          assert_empty(@state.validator_errors)
        end

        def test_coerce_input_value_returns_validator_error_when_validation_fails
          type = get_type("ValidatedFieldsInput")
          result = @input.coerce_input_value({ "scalar" => "a" }, type, state: @state)

          assert_equal({ scalar: "a" }, result)
          assert_empty(@state.coercion_errors)
          assert_equal(1, @state.validator_errors.size)
          assert_equal("scalar is too short (minimum is 2)", @state.validator_errors.first&.message)
          assert_equal(["scalar"], @state.validator_errors.first.path)
        end

        def test_coerce_input_value_returns_validator_error_for_invalid_default_value
          input_type = Class.new(GraphQL::Schema::InputObject) do
            graphql_name "InputWithBadDefault"
            argument :invalid_default, String, default_value: "a", validates: { length: { minimum: 2 } }
          end

          result = @input.coerce_input_value({}, input_type, state: @state)

          assert_equal({ invalid_default: "a" }, result)
          assert_empty(@state.coercion_errors)
          assert_equal(1, @state.validator_errors.size)
          assert_equal("invalidDefault is too short (minimum is 2)", @state.validator_errors.first&.message)
          assert_equal(["invalidDefault"], @state.validator_errors.first.path)
        end

        def test_coerce_input_value_collects_validator_errors_for_deeply_nested_failures
          type = get_type("ValidatedFieldsInput")
          input = {
            "scalar" => "a",  # fails at root
            "input" => {
              "scalar" => "b",  # fails at input.scalar
              "inputList" => [
                { "scalar" => "ab" },  # passes
                { "scalar" => "c" },   # fails at input.inputList.1.scalar
              ],
            },
          }
          expected = {
            scalar: "a",
            input: {
              scalar: "b",
              input_list: [
                { scalar: "ab" },
                { scalar: "c" },
              ],
            },
          }

          result = @input.coerce_input_value(input, type, state: @state)
          assert_equal(expected, result)
          assert_empty(@state.coercion_errors)
          assert_equal(3, @state.validator_errors.size)
          assert_equal(["scalar"], @state.validator_errors[0].path)
          assert_equal(["input", "scalar"], @state.validator_errors[1].path)
          assert_equal(["input", "inputList", 1, "scalar"], @state.validator_errors[2].path)
        end

        # === value_from_ast ===

        def test_value_from_ast_adds_error_for_no_input_ast_node
          type = get_type("String")
          result = @input.value_from_ast(nil, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Expected value node to be non-null.", @state.coercion_errors[0].message)
        end

        def test_value_from_ast_coerces_string_scalar
          type = get_type("String")
          ast = get_input_value_node('"hello"')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal("hello", result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_coerces_int_scalar
          type = get_type("Int")
          ast = get_input_value_node("42")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(42, result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_coerces_float_scalar
          type = get_type("Float")
          ast = get_input_value_node("3.14")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(3.14, result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_coerces_boolean_scalar
          type = get_type("Boolean")
          ast = get_input_value_node("true")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(true, result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_adds_error_for_invalid_scalar
          type = get_type("Int")
          ast = get_input_value_node('"not-an-int"')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Cannot represent non-Int value.", @state.coercion_errors.first&.message)
        end

        def test_value_from_ast_coerces_valid_enum
          type = get_type("TestStatus")
          ast = get_input_value_node("ACTIVE")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal("ACTIVE", result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_adds_error_for_non_enum_node
          type = get_type("TestStatus")
          ast = get_input_value_node('"ACTIVE"')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Expected value node to be an enum.", @state.coercion_errors[0].message)
        end

        def test_value_from_ast_returns_nil_for_null_value
          type = get_type("String")
          ast = get_input_value_node("null")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_nil(result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_adds_error_for_null_on_non_null_type
          type = get_type("String!")
          ast = get_input_value_node("null")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Expected value node to be non-null.", @state.coercion_errors[0].message)
        end

        def test_value_from_ast_coerces_valid_non_null_value
          type = get_type("String!")
          ast = get_input_value_node('"hello"')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal("hello", result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_coerces_array_for_list_type
          type = get_type("[String]")
          ast = get_input_value_node('["a", "b", "c"]')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(["a", "b", "c"], result)
          assert_predicate(result, :frozen?)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_wraps_single_value_as_array_for_list_type
          type = get_type("[String]")
          ast = get_input_value_node('"single"')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(["single"], result)
          assert_predicate(result, :frozen?)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_returns_nil_for_null_on_list_type
          type = get_type("[String]")
          ast = get_input_value_node("null")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_nil(result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_coerces_nested_list
          type = get_type("[[Int]]")
          ast = get_input_value_node("[[1, 2], [3]]")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal([[1, 2], [3]], result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_wraps_single_value_twice_for_nested_list
          type = get_type("[[Int]]")
          ast = get_input_value_node("42")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal([[42]], result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_wraps_each_item_for_nested_list
          type = get_type("[[Int]]")
          ast = get_input_value_node("[1, 2, 3]")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal([[1], [2], [3]], result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_preserves_null_values_in_nested_list
          type = get_type("[[Int]]")
          ast = get_input_value_node("[42, [null], null]")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal([[42], [nil], nil], result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_invalidates_entire_list_for_invalid_item
          type = get_type("[Int]")
          ast = get_input_value_node('[1, "not-an-int", 3]')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal([1], @state.coercion_errors[0].path)
        end

        def test_value_from_ast_invalidates_entire_list_for_null_as_non_null_list_item
          type = get_type("[String!]")
          ast = get_input_value_node('["ok", null, "also-ok"]')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal([1], @state.coercion_errors[0].path)
        end

        def test_value_from_ast_returns_error_for_list_with_object_literal
          type = get_type("[Boolean]")
          ast = get_input_value_node("{ foo: true }")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Cannot represent non-Boolean value.", @state.coercion_errors[0].message)
        end

        def test_value_from_ast_coerces_input_object
          type = get_type("TestInput")
          ast = get_input_value_node('{ string: "hello", int: 42 }')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal({ string: "hello", int: 42 }, result)
          assert_predicate(result, :frozen?)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_formats_keys_as_strings_when_symbolize_keys_disabled
          @input.symbolize_keys = false
          type = get_type("TestInput")
          ast = get_input_value_node('{ string: "hello", nestedList: [{ value: "a" }] }')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal({ "string" => "hello", "nestedList" => [{ "value" => "a" }] }, result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_uses_graphql_name_in_static_error_path
          type = get_type("TestInput")
          ast = get_input_value_node('{ stringList: [true] }')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(["stringList", 0], @state.coercion_errors.first.path)
        end

        def test_value_from_ast_adds_error_for_non_input_object_node
          type = get_type("TestInput")
          ast = get_input_value_node('"not-an-object"')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Expected value node to be an input object.", @state.coercion_errors[0].message)
        end

        def test_value_from_ast_adds_error_for_missing_required_field
          type = get_type("RequiredFieldsInput")
          ast = get_input_value_node('{ optional: "hello" }')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal(["required"], @state.coercion_errors[0].path)
          assert_equal('Expected argument "required" to be non-null.', @state.coercion_errors[0].message)
        end

        def test_value_from_ast_returns_undefined_for_nested_error
          type = get_type("TestInput")
          ast = get_input_value_node('{ nested: "not-an-object" }')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal(["nested"], @state.coercion_errors[0].path)
          assert_equal("Expected value node to be an input object.", @state.coercion_errors[0].message)
        end

        def test_value_from_ast_substitutes_variable
          type = get_type("String")
          ast = get_input_value_node("$myVar")
          result = @input.value_from_ast(ast, type, variables: { "myVar" => "from-variable" }, state: @state)

          assert_equal("from-variable", result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_adds_error_for_undefined_variable
          type = get_type("String")
          ast = get_input_value_node("$myVar")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Expected variable $myVar to be defined.", @state.coercion_errors[0].message)
        end

        def test_value_from_ast_adds_error_for_null_variable_on_non_null_type
          type = get_type("String!")
          ast = get_input_value_node("$myVar")
          result = @input.value_from_ast(ast, type, variables: { "myVar" => nil }, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Expected variable $myVar to be non-null.", @state.coercion_errors[0].message)
        end

        def test_value_from_ast_returns_nil_for_null_variable_on_nullable_type
          type = get_type("String")
          ast = get_input_value_node("$myVar")
          result = @input.value_from_ast(ast, type, variables: { "myVar" => nil }, state: @state)

          assert_nil(result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_substitutes_variable_in_list
          type = get_type("[String]")
          ast = get_input_value_node('["a", $myVar, "c"]')
          result = @input.value_from_ast(ast, type, variables: { "myVar" => "b" }, state: @state)

          assert_equal(["a", "b", "c"], result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_adds_error_for_missing_variable_as_non_null_list_item
          type = get_type("[String!]")
          ast = get_input_value_node('["a", $missingVar, "c"]')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal([1], @state.coercion_errors[0].path)
          assert_equal("Expected item to be non-null.", @state.coercion_errors[0].message)
        end

        def test_value_from_ast_returns_nil_for_missing_variable_as_nullable_list_item
          type = get_type("[String]")
          ast = get_input_value_node('["a", $missingVar, "c"]')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(["a", nil, "c"], result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_substitutes_variable_in_input_object_field
          type = get_type("TestInput")
          ast = get_input_value_node('{ string: $myVar }')
          result = @input.value_from_ast(ast, type, variables: { "myVar" => "from-variable" }, state: @state)

          assert_equal({ string: "from-variable" }, result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_adds_error_for_missing_variable_on_required_object_field
          type = get_type("RequiredFieldsInput")
          ast = get_input_value_node('{ required: $missingVar }')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal(["required"], @state.coercion_errors[0].path)
          assert_equal('Expected argument "required" to be non-null.', @state.coercion_errors[0].message)
        end

        def test_value_from_ast_returns_undefined_for_deeply_nested_error
          type = get_type("[TestInput]")
          ast = get_input_value_node('[{ nested: { value: "ok" } }, { nestedList: [{ value: "a" }, "not-an-object"] }]')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal([1, "nestedList", 1], @state.coercion_errors[0].path)
          assert_equal("Expected value node to be an input object.", @state.coercion_errors[0].message)
        end

        def test_value_from_ast_returns_nil_for_custom_scalar_returning_nil
          test_scalar = Class.new(GraphQL::Schema::Scalar) do
            graphql_name "ReturnNilScalar"

            class << self
              def coerce_input(_node, _context)
                nil
              end
            end
          end

          ast = get_input_value_node("value")
          result = @input.value_from_ast(ast, test_scalar, variables: {}, state: @state)

          assert_nil(result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_returns_message_for_custom_scalar_error
          test_scalar = Class.new(GraphQL::Schema::Scalar) do
            graphql_name "BrokenScalar"

            class << self
              def coerce_input(_node, _context)
                raise GraphQL::CoercionError, "Sorry, try again."
              end
            end
          end

          ast = get_input_value_node("value")
          result = @input.value_from_ast(ast, test_scalar, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Sorry, try again.", @state.coercion_errors[0].message)
        end

        def test_value_from_ast_returns_opaque_error_for_custom_scalar_exception
          test_scalar = Class.new(GraphQL::Schema::Scalar) do
            graphql_name "BrokenScalar"

            class << self
              def coerce_input(_node, _context)
                raise StandardError, "Boom"
              end
            end
          end

          ast = get_input_value_node("value")
          result = @input.value_from_ast(ast, test_scalar, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal('Expected type "BrokenScalar".', @state.coercion_errors[0].message)
        end

        def test_value_from_ast_returns_internal_value_for_mapped_enum
          test_enum = Class.new(GraphQL::Schema::Enum) do
            graphql_name "TestColor"
            value "RED", value: 1
            value "GREEN", value: 2
            value "BLUE", value: 3
          end

          ast = get_input_value_node("RED")
          result = @input.value_from_ast(ast, test_enum, variables: {}, state: @state)

          assert_equal(1, result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_returns_nil_for_enum_with_null_internal_value
          test_enum = Class.new(GraphQL::Schema::Enum) do
            graphql_name "NullableEnum"
            value "NULL_VALUE", value: nil
          end

          ast = get_input_value_node("NULL_VALUE")
          result = @input.value_from_ast(ast, test_enum, variables: {}, state: @state)

          assert_nil(result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_returns_error_for_invalid_enum_value
          type = get_type("TestStatus")
          ast = get_input_value_node("123")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Expected value node to be an enum.", @state.coercion_errors[0].message)
        end

        def test_value_from_ast_applies_default_value_for_input_object
          test_input = Class.new(GraphQL::Schema::InputObject) do
            graphql_name "InputWithDefault"
            argument :value, GraphQL::Types::Int, required: false, default_value: 42
            argument :other, GraphQL::Types::String, required: false
          end

          ast = get_input_value_node('{ other: "hello" }')
          result = @input.value_from_ast(ast, test_input, variables: {}, state: @state)

          assert_equal({ value: 42, other: "hello" }, result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_returns_error_for_input_object_with_array_literal
          type = get_type("TestInput")
          ast = get_input_value_node("[]")
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal("Expected value node to be an input object.", @state.coercion_errors[0].message)
        end

        def test_value_from_ast_does_not_wrap_list_variable_on_list_type
          type = get_type("[String]")
          ast = get_input_value_node("$myVar")
          result = @input.value_from_ast(ast, type, variables: { "myVar" => ["a", "b"] }, state: @state)

          assert_equal(["a", "b"], result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_does_not_wrap_single_variable_on_list_type
          # Note: variables are expected to have already been coerced,
          # so we do NOT expect the singleton wrapping behavior for variables.
          type = get_type("[String]")
          ast = get_input_value_node("$myVar")
          result = @input.value_from_ast(ast, type, variables: { "myVar" => "single" }, state: @state)

          assert_equal("single", result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_returns_null_for_missing_variable_on_nullable_list_item
          type = get_type("[String]")
          ast = get_input_value_node('[$missingVar]')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal([nil], result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_uses_default_for_missing_variable_in_input_object
          test_input = Class.new(GraphQL::Schema::InputObject) do
            graphql_name "InputWithDefault"
            argument :value, GraphQL::Types::Int, required: false, default_value: 42
            argument :other, GraphQL::Types::String, required: false
          end

          ast = get_input_value_node('{ value: $missing, other: "hello" }')
          result = @input.value_from_ast(ast, test_input, variables: {}, state: @state)

          assert_equal({ value: 42, other: "hello" }, result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_allows_one_of_with_single_non_null_value
          type = get_type("OneOfInput")
          ast = get_input_value_node('{ string: "a" }')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal({ string: "a" }, result)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_returns_error_for_one_of_with_null_value
          type = get_type("OneOfInput")
          ast = get_input_value_node('{ string: null }')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal('Exactly one value must be specified for OneOf type "OneOfInput", but "string" was null.', @state.coercion_errors[0].message)
        end

        def test_value_from_ast_returns_error_for_one_of_with_multiple_keys
          type = get_type("OneOfInput")
          ast = get_input_value_node('{ string: "a", int: 1 }')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal('Exactly one key must be specified for OneOf type "OneOfInput".', @state.coercion_errors[0].message)
        end

        def test_value_from_ast_returns_error_for_one_of_with_no_keys
          type = get_type("OneOfInput")
          ast = get_input_value_node('{}')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal('Exactly one key must be specified for OneOf type "OneOfInput".', @state.coercion_errors[0].message)
        end

        def test_value_from_ast_returns_nan_for_enum_with_nan_value
          test_enum = Class.new(GraphQL::Schema::Enum) do
            graphql_name "NanEnum"
            value "NAN", value: Float::NAN
          end

          ast = get_input_value_node("NAN")
          result = @input.value_from_ast(ast, test_enum, variables: {}, state: @state)

          assert_predicate(result, :nan?)
          assert_empty(@state.coercion_errors)
        end

        def test_value_from_ast_returns_name_for_enum_with_no_internal_value
          test_enum = Class.new(GraphQL::Schema::Enum) do
            graphql_name "NoValueEnum"
            value "NO_CUSTOM_VALUE"
          end

          ast = get_input_value_node("NO_CUSTOM_VALUE")
          result = @input.value_from_ast(ast, test_enum, variables: {}, state: @state)

          assert_equal("NO_CUSTOM_VALUE", result)
          assert_empty(@state.coercion_errors)
        end

        # === value_from_ast validation ===

        def test_value_from_ast_passes_validation
          type = get_type("ValidatedFieldsInput")
          ast = get_input_value_node('{ scalar: "ab" }')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal({ scalar: "ab" }, result)
          assert_empty(@state.coercion_errors)
          assert_empty(@state.validator_errors)
        end

        def test_value_from_ast_returns_validator_error_when_validation_fails
          type = get_type("ValidatedFieldsInput")
          ast = get_input_value_node('{ scalar: "a" }')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          assert_equal({ scalar: "a" }, result)
          assert_empty(@state.coercion_errors)
          assert_equal(1, @state.validator_errors.size)
          assert_equal("scalar is too short (minimum is 2)", @state.validator_errors.first&.message)
          assert_equal(["scalar"], @state.validator_errors.first.path)
        end

        def test_value_from_ast_returns_validator_error_for_invalid_default_value
          input_type = Class.new(GraphQL::Schema::InputObject) do
            graphql_name "InputWithBadDefault"
            argument :invalid_default, String, default_value: "a", validates: { length: { minimum: 2 } }
          end

          ast = get_input_value_node('{}')
          result = @input.value_from_ast(ast, input_type, variables: {}, state: @state)

          assert_equal({ invalid_default: "a" }, result)
          assert_empty(@state.coercion_errors)
          assert_equal(1, @state.validator_errors.size)
          assert_equal("invalidDefault is too short (minimum is 2)", @state.validator_errors.first&.message)
          assert_equal(["invalidDefault"], @state.validator_errors.first.path)
        end

        def test_value_from_ast_collects_validator_errors_for_deeply_nested_failures
          type = get_type("ValidatedFieldsInput")
          ast = get_input_value_node('{ scalar: "a", input: { scalar: "b", inputList: [{ scalar: "ab" }, { scalar: "c" }] } }')
          result = @input.value_from_ast(ast, type, variables: {}, state: @state)

          expected = {
            scalar: "a",
            input: {
              scalar: "b",
              input_list: [
                { scalar: "ab" },
                { scalar: "c" },
              ],
            },
          }
          assert_equal(expected, result)
          assert_empty(@state.coercion_errors)
          assert_equal(3, @state.validator_errors.size)
          assert_equal(["scalar"], @state.validator_errors[0].path)
          assert_equal(["input", "scalar"], @state.validator_errors[1].path)
          assert_equal(["input", "inputList", 1, "scalar"], @state.validator_errors[2].path)
        end

        # === format_default_value ===

        def test_format_default_value_returns_nil_for_nil
          type = get_type("String")
          result = @input.format_default_value(nil, type, state: @state)

          assert_nil(result)
          assert_empty(@state.coercion_errors)
        end

        def test_format_default_value_returns_unchanged_scalar_value
          type = get_type("String")
          result = @input.format_default_value("hello", type, state: @state)

          assert_equal("hello", result)
          assert_empty(@state.coercion_errors)
        end

        def test_format_default_value_formats_wrapped_non_null_type
          type = get_type("String!")
          result = @input.format_default_value("hello", type, state: @state)

          assert_equal("hello", result)
          assert_empty(@state.coercion_errors)
        end

        def test_format_default_value_formats_array_for_list_type
          type = get_type("[String]")
          result = @input.format_default_value(["a", "b", "c"], type, state: @state)

          assert_equal(["a", "b", "c"], result)
          assert_predicate(result, :frozen?)
          assert_empty(@state.coercion_errors)
        end

        def test_format_default_value_wraps_non_list_value_for_list_type
          type = get_type("[String]")
          result = @input.format_default_value("single", type, state: @state)

          assert_equal(["single"], result)
          assert_predicate(result, :frozen?)
          assert_empty(@state.coercion_errors)
        end

        def test_format_default_value_formats_nested_list
          type = get_type("[[Int]]")
          result = @input.format_default_value([[1, 2], [3]], type, state: @state)

          assert_equal([[1, 2], [3]], result)
          assert_empty(@state.coercion_errors)
        end

        def test_format_default_value_formats_input_object
          type = get_type("TestInput")
          result = @input.format_default_value({ "string" => "hello", "int" => 42 }, type, state: @state)

          assert_equal({ string: "hello", int: 42 }, result)
          assert_predicate(result, :frozen?)
          assert_empty(@state.coercion_errors)
        end

        def test_format_default_value_formats_keys_as_strings_when_symbolize_keys_disabled
          @input.symbolize_keys = false
          type = get_type("TestInput")

          input = {
            "string" => "hello",
            "nested" => { "value" => "deep" },
            "nestedList" => [{ "value" => "a" }, { "value" => "b" }],
          }
          result = @input.format_default_value(input, type, state: @state)

          assert_equal(input, result)
          assert_empty(@state.coercion_errors)
        end

        def test_format_default_value_uses_graphql_name_in_static_error_path
          type = get_type("TestInput")
          result = @input.format_default_value({ "nestedList" => [{ "unknown" => "x" }] }, type, state: @state)

          assert_equal({ nested_list: [{}] }, result)
          assert_equal(["nestedList", 0], @state.coercion_errors.first.path)
        end

        def test_format_default_value_formats_nested_input_object
          type = get_type("TestInput")
          result = @input.format_default_value({ "nested" => { "value" => "deep" } }, type, state: @state)

          assert_equal({ nested: { value: "deep" } }, result)
          assert_empty(@state.coercion_errors)
        end

        def test_format_default_value_adds_error_for_invalid_input_object
          type = get_type("TestInput")
          result = @input.format_default_value("not-an-object", type, state: @state)

          assert_equal(UNDEFINED, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal('Expected default value for type "TestInput" to be an object.', @state.coercion_errors[0].message)
        end

        def test_format_default_value_adds_error_for_unknown_field
          type = get_type("TestInput")
          result = @input.format_default_value({ "unknownField" => "value" }, type, state: @state)

          assert_equal({}, result)
          assert_equal(1, @state.coercion_errors.size)
          assert_equal('Invalid default field "unknownField" for type "TestInput".', @state.coercion_errors[0].message)
        end

        def test_format_default_value_formats_list_of_input_objects
          type = get_type("[NestedInput]")
          result = @input.format_default_value([{ "value" => "a" }, { "value" => "b" }], type, state: @state)

          assert_equal([{ value: "a" }, { value: "b" }], result)
          assert_empty(@state.coercion_errors)
        end

        # === format_default_value validations ===

        def test_format_default_value_passes_validation
          type = get_type("ValidatedFieldsInput")
          result = @input.format_default_value({ "scalar" => "ab" }, type, state: @state)

          assert_equal({ scalar: "ab" }, result)
          assert_empty(@state.coercion_errors)
          assert_empty(@state.validator_errors)
        end

        def test_format_default_value_returns_validator_error_when_validation_fails
          type = get_type("ValidatedFieldsInput")
          result = @input.format_default_value({ "scalar" => "a" }, type, state: @state)

          assert_equal({ scalar: "a" }, result)
          assert_empty(@state.coercion_errors)
          assert_equal(1, @state.validator_errors.size)
          assert_equal("scalar is too short (minimum is 2)", @state.validator_errors.first&.message)
          assert_equal(["scalar"], @state.validator_errors.first.path)
        end

        def test_format_default_value_collects_validator_errors_for_deeply_nested_failures
          type = get_type("ValidatedFieldsInput")
          default_value = {
            "scalar" => "a",  # fails at root
            "input" => {
              "scalar" => "b",  # fails at input.scalar
              "inputList" => [
                { "scalar" => "ab" },  # passes
                { "scalar" => "c" },   # fails at input.inputList.1.scalar
              ],
            },
          }
          expected = {
            scalar: "a",
            input: {
              scalar: "b",
              input_list: [
                { scalar: "ab" },
                { scalar: "c" },
              ],
            },
          }

          result = @input.format_default_value(default_value, type, state: @state)
          assert_equal(expected, result)
          assert_empty(@state.coercion_errors)
          assert_equal(3, @state.validator_errors.size)
          assert_equal(["scalar"], @state.validator_errors[0].path)
          assert_equal(["input", "scalar"], @state.validator_errors[1].path)
          assert_equal(["input", "inputList", 1, "scalar"], @state.validator_errors[2].path)
        end

        private

        #: (String) -> GraphQL::Language::Nodes::AbstractNode
        def get_variables_ast(vars_string)
          query = vars_string.empty? ? "{ __typename }" : "query(#{vars_string}) { __typename }"
          GraphQL.parse(query).definitions.first.variables
        end

        #: (String, String) -> GraphQL::Schema::Field
        def get_root_field(operation_type, field_name)
          TEST_SCHEMA.root_type_for_operation(operation_type).fields[field_name]
        end

        #: (String) -> GraphQL::Language::Nodes::Field
        def get_field_node(field_string)
          GraphQL.parse("mutation { #{field_string} }").definitions.first.selections.first
        end

        #: (String) -> GraphQL::Language::Nodes::AbstractNode
        def get_input_value_node(input_string)
          GraphQL.parse("{ field(input: #{input_string}) }").definitions.first.selections.first.arguments.first.value
        end

        #: (String) -> GraphQL::Language::Nodes::AbstractNode
        def get_type_node(type_string)
          GraphQL.parse("type T { field: #{type_string} }").definitions.first.fields.first.type
        end

        #: (String) -> singleton(GraphQL::Schema::Member)
        def get_type(type_string)
          @input.type_from_ast(get_type_node(type_string))
        end
      end
    end
  end
end
