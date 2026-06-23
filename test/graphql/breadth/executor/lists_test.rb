# frozen_string_literal: true

require "test_helper"

class ObjectPathResolver < GraphQL::Breadth::FieldResolver
  def resolve(exec_field, _ctx)
    exec_field.map_objects_with_index do |_object, index|
      "#{exec_field.scope.object_path(index).join(".")}|#{exec_field.object_path(index).join(".")}"
    end
  end
end

class GraphQL::Breadth::Executor::ListsTest < Minitest::Test
  TEST_SCHEMA = GraphQL::Schema.from_definition(%|
    enum WidgetStatus {
      YES
      NO
    }
    type Widget {
      parent: Widget
      title: String!
      status: WidgetStatus!
      titles: [String!]!
      statuses: [WidgetStatus!]!
      children: [Widget]!
      titleGroups: [[String!]!]!
      statusGroups: [[WidgetStatus!]!]!
      childGroups: [[Widget!]!]!
    }
    type Query {
      widget: Widget
    }
  |)

  TEST_RESOLVERS = {
    "Widget" => {
      "parent" => GraphQL::Breadth::HashKeyResolver.new("parent"),
      "title" => GraphQL::Breadth::HashKeyResolver.new("title"),
      "status" => GraphQL::Breadth::HashKeyResolver.new("status"),
      "titles" => GraphQL::Breadth::HashKeyResolver.new("titles"),
      "statuses" => GraphQL::Breadth::HashKeyResolver.new("statuses"),
      "children" => GraphQL::Breadth::HashKeyResolver.new("children"),
      "titleGroups" => GraphQL::Breadth::HashKeyResolver.new("titleGroups"),
      "statusGroups" => GraphQL::Breadth::HashKeyResolver.new("statusGroups"),
      "childGroups" => GraphQL::Breadth::HashKeyResolver.new("childGroups"),
    },
    "Query" => {
      "widget" => GraphQL::Breadth::HashKeyResolver.new("widget"),
    },
  }.freeze

  def test_resolves_flat_object_lists
    query = %|{
      widget {
        children {
          parent { title }
          title
          status
        }
      }
    }|

    source = {
      "widget" => {
        "children" => [{
          "parent" => { "title" => "Z" },
          "title" => "A",
          "status" => "YES",
        }, {
          "parent" => { "title" => "Z" },
          "title" => "B",
          "status" => "NO",
        }],
      },
    }

    result = execute_query(query, source)
    expected = { "data" => source }
    assert_equal expected, result
  end

  def test_resolves_nested_object_lists
    query = %|{
      widget {
        childGroups {
          parent { title }
          title
          status
        }
      }
    }|

    source = {
      "widget" => {
        "childGroups" => [
          [{
            "parent" => { "title" => "Z" },
            "title" => "A",
            "status" => "YES",
          }, {
            "parent" => { "title" => "Z" },
            "title" => "B",
            "status" => "NO",
          }], [{
            "parent" => { "title" => "Z" },
            "title" => "C",
            "status" => "YES",
          }],
        ],
      },
    }

    result = execute_query(query, source)
    expected = { "data" => source }
    assert_equal expected, result
  end

  def test_builds_exact_object_paths_for_nested_list_objects
    query = %|{
      widget {
        childGroups {
          title
        }
      }
    }|

    source = {
      "widget" => {
        "childGroups" => [
          [{ "title" => "A" }, { "title" => "B" }],
          [{ "title" => "C" }],
        ],
      },
    }

    resolvers = TEST_RESOLVERS.merge(
      "Widget" => TEST_RESOLVERS.fetch("Widget").merge("title" => ObjectPathResolver.new),
    )

    result = execute_query(query, source, resolvers: resolvers)

    assert_equal(
      {
        "data" => {
          "widget" => {
            "childGroups" => [
              [
                { "title" => "widget.childGroups.0.0|widget.childGroups.0.0.title" },
                { "title" => "widget.childGroups.0.1|widget.childGroups.0.1.title" },
              ],
              [
                { "title" => "widget.childGroups.1.0|widget.childGroups.1.0.title" },
              ],
            ],
          },
        },
      },
      result,
    )
  end

  def test_resolves_flat_leaf_lists
    query = %|{
      widget {
        titles
        statuses
      }
    }|

    source = {
      "widget" => {
        "titles" => ["A", "B"],
        "statuses" => ["YES", "NO"],
      },
    }

    result = execute_query(query, source)
    expected = { "data" => source }
    assert_equal expected, result
  end

  def test_resolves_nested_leaf_lists
    query = %|{
      widget {
        titleGroups
        statusGroups
      }
    }|

    source = {
      "widget" => {
        "titleGroups" => [["A", "B"], ["C", "D"]],
        "statusGroups" => [["YES", "NO"], ["YES", "YES"]],
      },
    }

    result = execute_query(query, source)
    expected = { "data" => source }
    assert_equal expected, result
  end

  private

  def execute_query(document, source, schema: TEST_SCHEMA, resolvers: TEST_RESOLVERS)
    GraphQL::Breadth::Executor.new(schema, GraphQL.parse(document), resolvers: resolvers, root_object: source).result
  end
end
