# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::DirectivesTest < Minitest::Test
  class RecordingDirectiveResolver < GraphQL::BreadthExec::DirectiveResolver
    attr_reader :calls

    def initialize(cascades: false)
      super(cascades: cascades)
      @calls = []
    end

    def resolve(exec_directive, _ctx, current_field: nil)
      @calls << {
        name: exec_directive.name,
        value: exec_directive.arguments[:value],
        path: current_field&.path,
      }
    end
  end

  class ReplaceDirectiveResolver < GraphQL::BreadthExec::DirectiveResolver
    def initialize
      super(wraps: true)
    end

    def resolve(exec_directive, _ctx, current_field: nil)
      current_field.result = current_field.resolve_all(exec_directive.arguments[:value])
    end
  end

  DIRECTIVE_SCHEMA = GraphQL::Schema.from_definition(%(
    directive @record(value: String) on QUERY | FIELD
    directive @replace(value: String!) on FIELD
    directive @cascade(value: String) on FIELD

    type Widget {
      title: String
      nested: Widget
    }

    type Query {
      widget: Widget
    }
  ))

  BASE_RESOLVERS = {
    "Widget" => {
      "title" => GraphQL::BreadthExec::HashKeyResolver.new("title"),
      "nested" => GraphQL::BreadthExec::HashKeyResolver.new("nested"),
    },
    "Query" => {
      "widget" => GraphQL::BreadthExec::HashKeyResolver.new("widget"),
    },
  }.freeze

  SOURCE = {
    "widget" => {
      "title" => "Original",
      "nested" => {
        "title" => "Nested",
      },
    },
  }.freeze

  def test_resolves_operation_and_field_directives
    record = RecordingDirectiveResolver.new
    resolvers = BASE_RESOLVERS.merge("@record" => record)

    document = GraphQL.parse(%|query @record(value: "root") {
      widget {
        title @record(value: "field")
      }
    }|)

    result = GraphQL::BreadthExec::Executor.new(DIRECTIVE_SCHEMA, document, resolvers: resolvers, root_object: SOURCE).perform

    assert_equal "Original", result.dig("data", "widget", "title")
    assert_equal [
      { name: "record", value: "root", path: nil },
      { name: "record", value: "field", path: ["widget", "title"] },
    ], record.calls
  end

  def test_builds_directives_from_schema_definitions
    document = GraphQL.parse(%|query @record(value: "root") { widget { title } }|)
    executor = GraphQL::BreadthExec::Executor.new(DIRECTIVE_SCHEMA, document, resolvers: BASE_RESOLVERS, root_object: SOURCE)
    operation = executor.query.selected_operation

    exec_directive = executor.planner.root_directives_for_operation(operation).first

    assert_same DIRECTIVE_SCHEMA.directives["record"], exec_directive.definition
  end

  def test_wrapping_field_directive_can_short_circuit_resolution
    replace = ReplaceDirectiveResolver.new
    resolvers = BASE_RESOLVERS.merge("@replace" => replace)

    document = GraphQL.parse(%|{
      widget {
        title @replace(value: "Overridden")
      }
    }|)

    result = GraphQL::BreadthExec::Executor.new(DIRECTIVE_SCHEMA, document, resolvers: resolvers, root_object: SOURCE).perform

    assert_equal "Overridden", result.dig("data", "widget", "title")
  end

  def test_invalid_directive_arguments_are_reported_then_raised_during_execution
    replace = ReplaceDirectiveResolver.new
    resolvers = BASE_RESOLVERS.merge("@replace" => replace)
    result = nil

    reported = assert_error_reported(GraphQL::BreadthExec::InputValidationErrorSet) do
      result = GraphQL::BreadthExec::Executor.new(
        DIRECTIVE_SCHEMA,
        GraphQL.parse(%|{ widget { title @replace } }|),
        resolvers: resolvers,
        root_object: SOURCE,
      ).perform
    end

    assert_equal ["Argument \"value\" of required type \"String!\" was not provided."], reported.errors.map(&:message)
    assert_equal(
      {
        "errors" => [
          {
            "message" => "Argument \"value\" of required type \"String!\" was not provided.",
            "locations" => [{ "line" => 1, "column" => 18 }],
            "path" => ["widget", "title"],
          },
        ],
        "data" => { "widget" => { "title" => nil } },
      },
      result,
    )
  end

  def test_cascading_field_directive_applies_to_descendants
    cascade = RecordingDirectiveResolver.new(cascades: true)
    resolvers = BASE_RESOLVERS.merge("@cascade" => cascade)

    document = GraphQL.parse(%|{
      widget @cascade(value: "all") {
        title
        nested {
          title
        }
      }
    }|)

    result = GraphQL::BreadthExec::Executor.new(DIRECTIVE_SCHEMA, document, resolvers: resolvers, root_object: SOURCE).perform

    assert_equal "Original", result.dig("data", "widget", "title")
    assert_equal "Nested", result.dig("data", "widget", "nested", "title")
    assert_equal [
      ["widget"],
      ["widget", "title"],
      ["widget", "nested"],
      ["widget", "nested", "title"],
    ], cascade.calls.map { _1[:path] }
  end
end
