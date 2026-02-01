# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::ArgumentsTest < Minitest::Test
  def test_arguments_receive_string_variables
    document = %|mutation($value: String!) {
      writeValue(value: $value) {
        value
      }
    }|

    source = { "writeValue" => { "value" => nil } }
    expected = { "writeValue" => { "value" => "success!" } }
    assert_equal expected, breadth_exec(document, source, variables: { "value" => "success!" }).dig("data")
  end

  def test_arguments_receive_symbol_variables
    document = %|mutation($value: String!) {
      writeValue(value: $value) {
        value
      }
    }|

    source = { "writeValue" => { "value" => nil } }
    expected = { "writeValue" => { "value" => "success!" } }
    assert_equal expected, breadth_exec(document, source, variables: { value: "success!" }).dig("data")
  end
end
