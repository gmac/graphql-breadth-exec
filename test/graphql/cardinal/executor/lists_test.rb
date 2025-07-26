# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::Executor::ListsTest < Minitest::Test
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
      "parent" => GraphQL::Cardinal::HashKeyResolver.new("parent"),
      "title" => GraphQL::Cardinal::HashKeyResolver.new("title"),
      "status" => GraphQL::Cardinal::HashKeyResolver.new("status"),
      "titles" => GraphQL::Cardinal::HashKeyResolver.new("titles"),
      "statuses" => GraphQL::Cardinal::HashKeyResolver.new("statuses"),
      "children" => GraphQL::Cardinal::HashKeyResolver.new("children"),
      "titleGroups" => GraphQL::Cardinal::HashKeyResolver.new("titleGroups"),
      "statusGroups" => GraphQL::Cardinal::HashKeyResolver.new("statusGroups"),
      "childGroups" => GraphQL::Cardinal::HashKeyResolver.new("childGroups"),
    },
    "Query" => {
      "widget" => GraphQL::Cardinal::HashKeyResolver.new("widget"),
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

  def execute_query(document, source, schema: TEST_SCHEMA)
    GraphQL::Cardinal::Executor.new(schema, TEST_RESOLVERS, GraphQL.parse(document), source).perform
  end
end
