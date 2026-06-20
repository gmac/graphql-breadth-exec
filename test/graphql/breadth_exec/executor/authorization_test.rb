# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::AuthorizationTest < Minitest::Test
  AUTH_SCHEMA = GraphQL::Schema.from_definition(%|
    type Widget {
      title: String
    }

    type Query {
      widget: Widget
      widgets: [Widget]
    }
  |)

  AUTH_RESOLVERS = {
    "Widget" => {
      "title" => GraphQL::BreadthExec::HashKeyResolver.new("title"),
    },
    "Query" => {
      "widget" => GraphQL::BreadthExec::HashKeyResolver.new("widget"),
      "widgets" => GraphQL::BreadthExec::HashKeyResolver.new("widgets"),
    },
  }.freeze

  SOURCE = {
    "widget" => { "title" => "Visible" },
    "widgets" => [
      { "title" => "Visible 1" },
      { "title" => "Hidden" },
      { "title" => "Visible 2" },
    ],
  }.freeze

  class RecordingAuthorization < GraphQL::BreadthExec::Authorization
    class << self
      attr_accessor :calls, :deny_field, :deny_type, :object_invalidations
    end

    def self.reset!
      self.calls = []
      self.deny_field = nil
      self.deny_type = nil
      self.object_invalidations = {}
    end

    reset!

    def authorized_field?(exec_field, context)
      self.class.calls << [:field, exec_field.path]
      exec_field.path != self.class.deny_field
    end

    def authorized_type?(type, context, exec_field: nil)
      self.class.calls << [:type, type.graphql_name, exec_field&.path]
      [type.graphql_name, exec_field&.path] != self.class.deny_type
    end

    def authorize_objects_in_scope?(exec_scope, context)
      self.class.calls << [:authorize_objects, exec_scope.parent_type.graphql_name, exec_scope.path]
      exec_scope.parent_type.graphql_name == "Widget"
    end

    def unauthorized_object_indices(exec_scope, context)
      self.class.calls << [:objects, exec_scope.parent_type.graphql_name, exec_scope.path]
      self.class.object_invalidations.fetch(exec_scope.path, GraphQL::BreadthExec::EMPTY_OBJECT)
    end
  end

  def setup
    RecordingAuthorization.reset!
  end

  def execute(document)
    GraphQL::BreadthExec::Executor.new(
      AUTH_SCHEMA,
      GraphQL.parse(document),
      resolvers: AUTH_RESOLVERS,
      root_object: SOURCE,
      authorization: RecordingAuthorization,
    ).perform
  end

  def test_checks_field_authorization_before_resolving_field
    RecordingAuthorization.deny_field = ["widget", "title"]

    result = execute(%|{
      widget {
        title
      }
    }|)

    assert_equal({ "widget" => { "title" => nil } }, result["data"])
    assert_equal "Not authorized", result.dig("errors", 0, "message")
    assert_equal ["widget", "title"], result.dig("errors", 0, "path")
    assert_includes RecordingAuthorization.calls, [:field, ["widget", "title"]]
  end

  def test_checks_type_authorization_for_scopes
    RecordingAuthorization.deny_type = ["Widget", ["widget"]]

    result = execute(%|{
      widget {
        title
      }
    }|)

    assert_equal({ "widget" => nil }, result["data"])
    assert_equal "Not authorized", result.dig("errors", 0, "message")
    assert_equal ["widget"], result.dig("errors", 0, "path")
    assert_includes RecordingAuthorization.calls, [:type, "Widget", ["widget"]]
  end

  def test_invalidates_unauthorized_objects_before_scope_execution
    RecordingAuthorization.object_invalidations = {
      ["widgets"] => {
        1 => GraphQL::BreadthExec::ExecutionError.new("Object hidden"),
      },
    }

    result = execute(%|{
      widgets {
        title
      }
    }|)

    assert_equal(
      {
        "widgets" => [
          { "title" => "Visible 1" },
          nil,
          { "title" => "Visible 2" },
        ],
      },
      result["data"],
    )
    assert_equal "Object hidden", result.dig("errors", 0, "message")
    assert_equal ["widgets", 1], result.dig("errors", 0, "path")
    assert_includes RecordingAuthorization.calls, [:objects, "Widget", ["widgets"]]
  end
end
