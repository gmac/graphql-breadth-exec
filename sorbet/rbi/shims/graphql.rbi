# typed: true

module GraphQL
  class Error < StandardError; end

  class AnalysisError < StandardError
    def to_h; end
  end

  class ExecutionError < StandardError
    def initialize(message = T.unsafe(nil), **kwargs); end
    def extensions; end
    def path; end
  end

  class UnauthorizedError < StandardError; end

  class Query
    class Context
      def [](key); end
      def []=(key, value); end
      def errors; end
      def namespace?(key); end
      def namespace(key); end
      def query; end
      def types; end
    end

    def initialize(schema, query_string = T.unsafe(nil), document: T.unsafe(nil), operation_name: T.unsafe(nil), variables: T.unsafe(nil), validate: T.unsafe(nil), root_value: T.unsafe(nil), context: T.unsafe(nil)); end
    def context; end
    def fragments; end
    def schema; end
    def selected_operation; end
    def root_type_for_operation(operation_type); end
    def get_type(type_name); end
    def get_field(parent_type, field_name); end
    def possible_types(type); end
    def resolve_type(type, object); end
    def types; end
    def validation_errors; end
    def provided_variables; end
  end

  module Execution
    module Errors
      def self.find_handler_for(schema, error_class); end
    end
  end

  module Language
    class DocumentFromSchemaDefinition
      def initialize(schema, context: T.unsafe(nil)); end
    end

    class Printer
      def initialize; end
    end

    module Nodes
      class AbstractNode
        def col; end
        def line; end
      end

      class Document < AbstractNode; end

      class OperationDefinition < AbstractNode
        def directives; end
        def operation_type; end
        def selections; end
        def variables; end
      end

      class FragmentDefinition < AbstractNode
        def name; end
        def selections; end
        def type; end
      end

      class Field < AbstractNode
        def alias; end
        def arguments; end
        def directives; end
        def name; end
        def selections; end
      end

      class InlineFragment < AbstractNode
        def directives; end
        def selections; end
        def type; end
      end

      class FragmentSpread < AbstractNode
        def directives; end
        def name; end
      end

      class Directive < AbstractNode
        def arguments; end
        def name; end
      end

      class VariableIdentifier < AbstractNode
        def name; end
      end

      class VariableDefinition < AbstractNode
        def default_value; end
        def name; end
        def type; end
      end

      class NullValue < AbstractNode; end

      class WrapperType < AbstractNode
        sig { returns(WrapperType) }
        def of_type; end
      end

      class ListType < WrapperType; end

      class NonNullType < WrapperType; end

      class InputObject < AbstractNode
        def arguments; end
      end

      class Argument < AbstractNode
        def name; end
        def value; end
      end

      class Enum < AbstractNode
        def name; end
      end
    end
  end

  class Schema
    def self.directives; end
    def self.query; end
    def self.lazy?(value); end
    def self.sync_lazy(value); end
    def self.type_error(error, context); end

    def directives; end
    def query; end
    def lazy?(value); end
    def sync_lazy(value); end
    def type_error(error, context); end

    class Member
      def self.graphql_name; end
      def self.kind; end
      def self.unwrap; end
      def self.list?; end
      def self.non_null?; end
      def self.of_type; end
      def self.to_type_signature; end
      def self.to_list_type; end
      def self.to_non_null_type; end
      def self.const_get(name); end

      def graphql_name; end
      def kind; end
      def unwrap; end
      def list?; end
      def non_null?; end
      def of_type; end
      def to_type_signature; end
      def to_list_type; end
      def to_non_null_type; end
      def const_get(name); end
    end

    class Object < Member
      def self.introspection?; end

      def introspection?; end
    end

    class InputObject < Member
      def self.directives; end

      def directives; end
    end

    class Field
      def graphql_name; end
      def name; end
      def original_name; end
      def resolver; end
      def type; end
      def path; end
      def introspection?; end
    end

    class Argument
      def default_value; end
      def default_value?; end
      def graphql_name; end
      def keyword; end
      def type; end
    end

    class Directive
      def graphql_name; end
    end
  end
end
