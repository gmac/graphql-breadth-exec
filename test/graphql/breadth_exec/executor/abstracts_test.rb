# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::AbstractsTest < Minitest::Test
  class TypeErrorField < GraphQL::Schema::Field
    include GraphQL::BreadthExec::HasBreadthResolver::Field
  end

  module TypeErrorNode
    include GraphQL::Schema::Interface

    field :id, String, null: true
  end

  class TypeErrorProduct < GraphQL::Schema::Object
    implements TypeErrorNode
    field_class TypeErrorField

    field :id, String, null: true do |field|
      field.breadth_resolver = GraphQL::BreadthExec::HashKeyResolver.new("id")
    end
  end

  class TypeErrorQuery < GraphQL::Schema::Object
    field_class TypeErrorField

    field :node, TypeErrorNode, null: true do |field|
      field.breadth_resolver = GraphQL::BreadthExec::HashKeyResolver.new("node")
    end
  end

  class TypeErrorSchema < GraphQL::Schema
    query TypeErrorQuery
    orphan_types TypeErrorProduct

    class << self
      attr_accessor :type_errors

      def resolve_type(_abstract_type, _object, _context)
        nil
      end

      def type_error(error, context)
        self.type_errors ||= []
        type_errors << [error, context]
      end
    end
  end

  def test_abstract_type_object_access
    document = %|{
      node(id: "Product/1") {
        ... on Product { id }
        __typename
      }
    }|

    source = {
      "node" => { "id" => "Product/1", "__typename__" => "Product" },
    }

    expected = {
      "node" => { "id" => "Product/1", "__typename" => "Product" },
    }

    assert_equal expected, breadth_exec(document, source).dig("data")
  end

  def test_abstract_type_list_access
    document = %|{
      nodes(ids: ["Product/1", "Variant/1"]) {
        __typename
        ... on Product {
          id
        }
        ... on Variant {
          title
        }
      }
    }|

    source = {
      "nodes" => [
        { "id" => "Product/1", "title" => "Product 1", "__typename__" => "Product" },
        { "id" => "Variant/1", "title" => "Variant 1", "__typename__" => "Variant" },
      ],
    }

    expected = {
      "nodes" => [
        { "id" => "Product/1", "__typename" => "Product" },
        { "title" => "Variant 1", "__typename" => "Variant" },
      ],
    }

    assert_equal expected, breadth_exec(document, source).dig("data")
  end

  def test_unresolved_abstract_type_reports_basic_schema_type_error
    TypeErrorSchema.type_errors = []
    executor = GraphQL::BreadthExec::Executor.new(
      TypeErrorSchema,
      GraphQL.parse(%|{ node { id } }|),
      root_object: { "node" => { "id" => "Product/1" } },
    )

    assert_raises(GraphQL::BreadthExec::ImplementationError) { executor.perform }

    error, context = TypeErrorSchema.type_errors.first
    assert_kind_of GraphQL::UnresolvedTypeError, error
    assert_instance_of GraphQL::Query::Context, context
  end
end
