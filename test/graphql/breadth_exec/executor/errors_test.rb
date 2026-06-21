# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::ErrorsTest < Minitest::Test
  BUILD_ERROR_SCHEMA = GraphQL::Schema.from_definition(%|
    type Query {
      badList: [String]
      ok: String
    }
  |)

  BUILD_ERROR_SCHEMA.rescue_from(GraphQL::BreadthExec::InvalidListResultError) do
    GraphQL::ExecutionError.new("Handled build error")
  end

  BUILD_ERROR_RESOLVERS = {
    "Query" => {
      "badList" => GraphQL::BreadthExec::HashKeyResolver.new("badList"),
      "ok" => GraphQL::BreadthExec::HashKeyResolver.new("ok"),
    },
  }.freeze

  class NilResultScalar < GraphQL::Schema::Scalar
    graphql_name "NilResult"

    def self.coerce_result(_value, _context)
      nil
    end
  end

  class ErrorResultScalar < GraphQL::Schema::Scalar
    graphql_name "ErrorResult"

    def self.coerce_result(_value, _context)
      raise GraphQL::ExecutionError, "Cannot coerce result"
    end
  end

  class ResultCoercionField < GraphQL::Schema::Field
    include GraphQL::BreadthExec::HasBreadthResolver::Field
  end

  class ResultCoercionQuery < GraphQL::Schema::Object
    field_class ResultCoercionField

    field :nullable_nil, NilResultScalar, null: true do |field|
      field.breadth_resolver = GraphQL::BreadthExec::HashKeyResolver.new("nullableNil")
    end

    field :required_nil, NilResultScalar, null: false do |field|
      field.breadth_resolver = GraphQL::BreadthExec::HashKeyResolver.new("requiredNil")
    end

    field :nullable_error, ErrorResultScalar, null: true do |field|
      field.breadth_resolver = GraphQL::BreadthExec::HashKeyResolver.new("nullableError")
    end
  end

  class ResultCoercionSchema < GraphQL::Schema
    query ResultCoercionQuery

    class << self
      attr_accessor :type_errors

      def type_error(error, context)
        self.type_errors ||= []
        type_errors << [error, context]
        super
      end
    end
  end

  def test_nullable_positional_error_adds_path
    document = %|{
      products(first: 3) {
        nodes {
          maybe
        }
      }
    }|

    source = {
      "products" => {
        "nodes" => [
          { "maybe" => "okay!" },
          { "maybe" => nil },
          { "maybe" => GraphQL::BreadthExec::ExecutionError.new("Not okay!") },
        ],
      },
    }

    expected = {
      "data" => {
        "products" => {
          "nodes" => [
            { "maybe" => "okay!" },
            { "maybe" => nil },
            { "maybe" => nil },
          ],
        },
      },
      "errors" => [{
        "message" => "Not okay!",
        "locations" => [{ "line" => 4, "column" => 11 }],
        "path" => ["products", "nodes", 2, "maybe"],
      }],
    }

    assert_equal expected, breadth_exec(document, source)
  end

  def test_handled_build_result_error_stays_field_local
    document = GraphQL.parse(%|{
      badList
      ok
    }|)

    source = {
      "badList" => "not a list",
      "ok" => "still here",
    }

    expected = {
      "data" => {
        "badList" => nil,
        "ok" => "still here",
      },
      "errors" => [{
        "message" => "Handled build error",
        "locations" => [{ "line" => 2, "column" => 7 }],
        "path" => ["badList"],
      }],
    }

    executor = GraphQL::BreadthExec::Executor.new(BUILD_ERROR_SCHEMA, document, resolvers: BUILD_ERROR_RESOLVERS, root_object: source)
    assert_equal expected, executor.result
  end

  def test_nullable_scalar_result_coerced_to_nil_builds_missing_value_without_error
    result = execute_result_coercion_query(%|{ nullableNil }|, { "nullableNil" => "nope" })

    assert_equal({ "data" => { "nullableNil" => nil } }, result)
  end

  def test_non_null_scalar_result_coerced_to_nil_propagates_invalid_null
    result = execute_result_coercion_query(%|{ requiredNil }|, { "requiredNil" => "nope" })

    assert_equal(
      {
        "errors" => [{
          "message" => "Cannot return null for non-nullable field ResultCoercionQuery.requiredNil",
          "locations" => [{ "line" => 1, "column" => 3 }],
          "path" => ["requiredNil"],
          "extensions" => { "code" => "INVALID_NULL" },
        }],
        "data" => nil,
      },
      result,
    )

    error, context = ResultCoercionSchema.type_errors.first
    assert_kind_of GraphQL::InvalidNullError, error
    assert_instance_of GraphQL::Query::Context, context
  end

  def test_scalar_result_coercion_error_is_handled_as_execution_error
    result = execute_result_coercion_query(%|{ nullableError }|, { "nullableError" => "nope" })

    assert_equal(
      {
        "errors" => [{
          "message" => "Cannot coerce result",
          "locations" => [{ "line" => 1, "column" => 3 }],
          "path" => ["nullableError"],
        }],
        "data" => { "nullableError" => nil },
      },
      result,
    )
  end

  def test_non_null_positional_error_adds_path_and_propagates
    document = %|{
      products(first: 3) {
        nodes {
          must
        }
      }
    }|

    source = {
      "products" => {
        "nodes" => [
          { "must" => "okay!" },
          { "must" => GraphQL::BreadthExec::ExecutionError.new("Not okay!") },
        ],
      },
    }

    expected = {
      "data" => {
        "products" => nil,
      },
      "errors" => [{
        "message" => "Not okay!",
        "locations" => [{ "line" => 4, "column" => 11 }],
        "path" => ["products", "nodes", 1, "must"],
      }],
    }

    assert_equal expected, breadth_exec(document, source)
  end

  def test_null_in_non_null_position_propagates
    document = %|{
      products(first: 3) {
        nodes {
          must
        }
      }
    }|

    source = {
      "products" => {
        "nodes" => [
          { "must" => "okay!" },
          { "must" => nil },
        ],
      },
    }

    expected = {
      "data" => {
        "products" => nil,
      },
      "errors" => [{
        "message" => "Cannot return null for non-nullable field Product.must",
        "locations" => [{ "line" => 4, "column" => 11 }],
        "path" => ["products", "nodes", 1, "must"],
        "extensions" => { "code" => "INVALID_NULL" },
      }],
    }

    assert_equal expected, breadth_exec(document, source)
  end

  private

  def execute_result_coercion_query(document, source)
    ResultCoercionSchema.type_errors = []

    GraphQL::BreadthExec::Executor.new(
      ResultCoercionSchema,
      GraphQL.parse(document),
      root_object: source,
    ).result
  end
end
