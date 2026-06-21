# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::HasBreadthResolverTest < Minitest::Test
  class LanguageDirectiveResolver < GraphQL::BreadthExec::DirectiveResolver
    def resolve(exec_directive, context, current_field: nil)
      context[:language] = exec_directive.arguments[:language]
    end
  end

  class LanguageFieldResolver < GraphQL::BreadthExec::FieldResolver
    def resolve(exec_field, context)
      exec_field.resolve_all(context[:language])
    end
  end

  class BaseField < GraphQL::Schema::Field
    include GraphQL::BreadthExec::HasBreadthResolver::Field
  end

  class InContext < GraphQL::Schema::Directive
    extend GraphQL::BreadthExec::HasBreadthResolver::Directive

    self.breadth_resolver = LanguageDirectiveResolver.new

    graphql_name "inContext"
    locations QUERY
    argument :language, String, required: true
  end

  class Widget < GraphQL::Schema::Object
    field_class BaseField

    field :id, String, null: true do |field|
      field.breadth_resolver = GraphQL::BreadthExec::HashKeyResolver.new("id")
    end
  end

  class Query < GraphQL::Schema::Object
    field_class BaseField

    field :widget, Widget, null: true do |field|
      field.breadth_resolver = GraphQL::BreadthExec::HashKeyResolver.new("widget")
    end

    field :language, String, null: true do |field|
      field.breadth_resolver = LanguageFieldResolver.new
    end

    field :fallback, String, null: true
  end

  class TestSchema < GraphQL::Schema
    query Query
    directive InContext
  end

  MockObject = Struct.new(:method_field, keyword_init: true)

  class ShortcutQuery < GraphQL::Schema::Object
    field_class BaseField

    field :method_field, String, null: true do |field|
      field.breadth_resolver = :method
    end

    field :symbol_hash_field, String, null: true do |field|
      field.breadth_resolver = :hash_key_symbol
    end

    field :string_hash_field, String, null: true do |field|
      field.breadth_resolver = :hash_key_string
    end

    field :itself_field, String, null: true do |field|
      field.breadth_resolver = :itself
    end
  end

  class ShortcutSchema < GraphQL::Schema
    query ShortcutQuery
  end

  def test_field_breadth_resolver_is_preferred_over_resolver_map
    resolvers = {
      "Query" => {
        "widget" => GraphQL::BreadthExec::ValueResolver.new({ "id" => "map" }),
      },
    }

    result = execute(TestSchema, %|{ widget { id } }|, { "widget" => { "id" => "field" } }, resolvers:)

    assert_equal({ "data" => { "widget" => { "id" => "field" } } }, result)
  end

  def test_directive_breadth_resolver_is_preferred_over_resolver_map
    resolvers = {
      "@inContext" => GraphQL::BreadthExec::ValueResolver.new("unused"),
    }

    result = execute(TestSchema, %|query @inContext(language: "DE") { language }|, {}, resolvers:)

    assert_equal({ "data" => { "language" => "DE" } }, result)
  end

  def test_falls_back_to_resolver_map_without_field_breadth_resolver
    resolvers = {
      "Query" => {
        "fallback" => GraphQL::BreadthExec::ValueResolver.new("from-map"),
      },
    }

    result = execute(TestSchema, %|{ fallback }|, {}, resolvers:)

    assert_equal({ "data" => { "fallback" => "from-map" } }, result)
  end

  def test_symbol_shortcuts
    method_result = execute(ShortcutSchema, %|{ methodField }|, MockObject.new(method_field: "from-method"))
    symbol_hash_result = execute(ShortcutSchema, %|{ symbolHashField }|, { symbol_hash_field: "from-symbol" })
    string_hash_result = execute(ShortcutSchema, %|{ stringHashField }|, { "string_hash_field" => "from-string" })
    itself_result = execute(ShortcutSchema, %|{ itselfField }|, "from-self")

    assert_equal({ "data" => { "methodField" => "from-method" } }, method_result)
    assert_equal({ "data" => { "symbolHashField" => "from-symbol" } }, symbol_hash_result)
    assert_equal({ "data" => { "stringHashField" => "from-string" } }, string_hash_result)
    assert_equal({ "data" => { "itselfField" => "from-self" } }, itself_result)
  end

  def test_invalid_symbol_breadth_resolver_raises_error
    error = assert_raises(GraphQL::BreadthExec::ImplementationError) do
      query_type = Class.new(GraphQL::Schema::Object) do
        graphql_name "BadQuery"
        field_class BaseField

        field :bad, String, null: true do |field|
          field.breadth_resolver = :nope
        end
      end

      Class.new(GraphQL::Schema) do
        query(query_type)
      end
    end

    assert_equal "Invalid breadth resolver keyword: nope. Expected one of method, hash_key_symbol, hash_key_string, itself.", error.message
  end

  private

  def execute(schema, document, source, resolvers: GraphQL::BreadthExec::EMPTY_OBJECT)
    GraphQL::BreadthExec::Executor.new(
      schema,
      GraphQL.parse(document),
      resolvers: resolvers,
      root_object: source,
    ).result
  end
end
