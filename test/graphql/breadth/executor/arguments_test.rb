# frozen_string_literal: true

require "test_helper"

class GraphQL::Breadth::Executor::ArgumentsTest < Minitest::Test
  def test_arguments_receive_string_variables
    document = %|mutation($value: String!) {
      writeValue(value: $value) {
        value
      }
    }|

    source = { "writeValue" => { "value" => nil } }
    expected = { "writeValue" => { "value" => "success!" } }
    assert_equal expected, breadth(document, source, variables: { "value" => "success!" }).dig("data")
  end

  def test_arguments_receive_symbol_variables
    document = %|mutation($value: String!) {
      writeValue(value: $value) {
        value
      }
    }|

    source = { "writeValue" => { "value" => nil } }
    expected = { "writeValue" => { "value" => "success!" } }
    assert_equal expected, breadth(document, source, variables: { value: "success!" }).dig("data")
  end

  def test_invalid_field_arguments_are_reported_then_raised_during_execution
    result = nil

    reported = assert_error_reported(GraphQL::Breadth::InputValidationErrorSet) do
      result = breadth(
        %|mutation { writeValue { value } }|,
        { "writeValue" => { "value" => "unchanged" } },
      )
    end

    assert_equal ["Argument \"value\" of required type \"String!\" was not provided."], reported.errors.map(&:message)
    assert_equal(
      {
        "errors" => [
          {
            "message" => "Argument \"value\" of required type \"String!\" was not provided.",
            "locations" => [{ "line" => 1, "column" => 12 }],
            "path" => ["writeValue"],
          },
        ],
        "data" => { "writeValue" => nil },
      },
      result,
    )
  end
end
