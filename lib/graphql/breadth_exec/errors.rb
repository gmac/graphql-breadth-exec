# typed: true
# frozen_string_literal: true

require "graphql"

module GraphQL
  module BreadthExec
    class Error < StandardError; end
    class DocumentError < Error; end
    class ImplementationError < Error; end
    class MethodNotImplementedError < Error; end

    #: type error_hash = Hash[String, untyped]
    #: type extensions_hash = Hash[String | Symbol, untyped]

    class ExecutionError < Error
      class << self
        #: String
        attr_accessor :error_code

        #: (
        #|   untyped,
        #|   ?exec_field: GraphQL::BreadthExec::Executor::ExecutionField[untyped]?,
        #|   ?cause: Exception?
        #| ) -> ExecutionError
        def from(err, exec_field: nil, cause: nil)
          return err if err.equal?(UNREPORTED_ERROR)

          case err
          when BreadthExec::ExecutionError
            if err.exec_field != exec_field || err.cause != cause
              err = err.dup
              err.exec_field = exec_field if exec_field
              err.cause = cause if cause
            end
            err
          when GraphQL::ExecutionError
            new(err.message, exec_field:, extensions: err.extensions, cause: cause || err)
          when StandardError
            new(exec_field:, cause: cause || err)
          when String
            new(err, exec_field:, cause:)
          else
            new(exec_field:, cause:)
          end
        end
      end

      DEFAULT_MESSAGE = "An unknown error occurred"

      #: GraphQL::BreadthExec::Executor::ExecutionField[untyped]?
      attr_accessor :exec_field

      #: Exception?
      attr_accessor :cause

      #: extensions_hash?
      attr_reader :extensions

      #: error_path?
      attr_reader :path

      #: (
      #|   ?String?,
      #|   ?exec_field: GraphQL::BreadthExec::Executor::ExecutionField[untyped]?,
      #|   ?nodes: Array[GraphQL::Language::Nodes::AbstractNode],
      #|   ?extensions: extensions_hash?,
      #|   ?cause: Exception?,
      #|   ?path: error_path?,
      #|   ?base: bool,
      #| ) -> void
      def initialize(message = nil, exec_field: nil, nodes: EMPTY_ARRAY, extensions: nil, cause: nil, path: nil, base: false)
        super(message || DEFAULT_MESSAGE)
        @exec_field = exec_field
        @cause = cause
        @nodes = nodes
        @extensions = extensions
        @path = path
        @base = base

        if self.class.error_code
          @extensions ||= {}
          @extensions["code"] ||= self.class.error_code
        end
      end

      #: () -> Array[GraphQL::Language::Nodes::AbstractNode]
      def nodes
        @nodes.empty? && @exec_field ? @exec_field.nodes : @nodes
      end

      #: () -> error_hash
      def to_h
        hash = { "message" => message }
        hash["locations"] = nodes.map { { "line" => _1.line, "column" => _1.col } } unless nodes.empty?
        hash["path"] = path if path
        hash["extensions"] = Util.deep_copy(extensions, stringify_keys: true) if extensions && !extensions&.empty?
        hash
      end

      #: () -> bool
      def base_error?
        @base
      end

      #: (error_path) -> void
      def replace_path(new_path)
        @path = new_path
      end

      #: { (ExecutionError) -> void } -> void
      def each(&block)
        [self].each(&block)
      end
    end

    class ExecutionErrorSet < ExecutionError
      #: Array[ExecutionError]
      attr_reader :errors

      #: (
      #|   ?String?,
      #|   ?exec_field: GraphQL::BreadthExec::Executor::ExecutionField[untyped]?,
      #|   ?errors: Array[ExecutionError],
      #| ) -> void
      def initialize(message = nil, exec_field: nil, errors: [])
        @errors = errors
        super(message || errors.map(&:message).join(", "), exec_field:)
      end

      #: (
      #|   ?String?,
      #|   ?extensions: extensions_hash?,
      #|   ?cause: Exception?,
      #| ) -> ExecutionErrorSet
      def add_error(message = nil, extensions: nil, cause: nil)
        @errors << ExecutionError.new(message, exec_field:, extensions:, cause:)
        self
      end

      #: () -> Array[GraphQL::Language::Nodes::AbstractNode]
      def nodes
        @errors.flat_map(&:nodes)
      end

      #: { (ExecutionError) -> void } -> void
      def each(&block)
        @errors.each(&block)
      end
    end

    class FieldAuthorizationError < ExecutionError
      MESSAGE = "Not authorized"

      #: (
      #|   ?String?,
      #|   exec_field: GraphQL::BreadthExec::Executor::ExecutionField[untyped],
      #|   ?extensions: extensions_hash?,
      #|   ?cause: Exception?,
      #| ) -> void
      def initialize(message = nil, exec_field:, extensions: nil, cause: nil)
        super(message || MESSAGE, exec_field:, extensions:, cause:)
      end
    end

    class InvalidNullError < ExecutionError
      self.error_code = "INVALID_NULL".freeze

      #: (?String?, exec_field: GraphQL::BreadthExec::Executor::ExecutionField[untyped], ?list_item: bool) -> void
      def initialize(message = nil, exec_field:, list_item: false)
        message ||= if list_item
          list_type = Util.unwrap_non_null(exec_field.type)
          "Cannot return null for non-nullable element of type '#{list_type.of_type.to_type_signature}' for #{exec_field.scope.parent_type.graphql_name}.#{exec_field.name}"
        else
          "Cannot return null for non-nullable field #{exec_field.scope.parent_type.graphql_name}.#{exec_field.name}"
        end

        super(message, exec_field:)
      end
    end

    class OperationTypeUnsupportedError < ExecutionError
      #: (String) -> void
      def initialize(operation_type)
        @operation_type = operation_type
        super("Unsupported operation type")
      end

      #: () -> error_hash
      def to_h
        super.tap do |hash|
          hash["path"] = [@operation_type]
        end
      end
    end

    class InputError < ExecutionError
      #: (
      #|   String message,
      #|   ?path: error_path,
      #|   ?nodes: Array[GraphQL::Language::Nodes::AbstractNode],
      #|   ?extensions: extensions_hash?,
      #| ) -> void
      def initialize(message, path: EMPTY_ARRAY, nodes: EMPTY_ARRAY, extensions: nil)
        super(message, path:, nodes:, extensions:)
      end

      #: (GraphQL::Language::Nodes::AbstractNode) -> void
      def add_parent_node(node)
        return if @nodes.include?(node)

        @nodes = @nodes.dup if @nodes.frozen?
        @nodes.prepend(node)
      end
    end

    class InputCoercionError < InputError; end

    class InputValidatorError < InputError
      self.error_code = "INVALID_INPUT".freeze
    end

    class InputValidationErrorSet < ExecutionErrorSet; end

    class InvalidListResultError < ImplementationError
      #: GraphQL::BreadthExec::Executor::ExecutionField[untyped]
      attr_reader :exec_field

      #: Class
      attr_reader :result_type

      #: (
      #|   exec_field: GraphQL::BreadthExec::Executor::ExecutionField[untyped],
      #|   result_type: Class,
      #| ) -> void
      def initialize(exec_field:, result_type:)
        @exec_field = exec_field
        @result_type = result_type
        super("Incorrect result for list field `#{exec_field.path.join(".")}`. Expected Array, got `#{result_type}`")
      end
    end

    class ResultCountMismatchError < ImplementationError
      #: GraphQL::BreadthExec::Executor::ExecutionField[untyped]
      attr_reader :exec_field

      #: Integer
      attr_reader :expected_count

      #: Integer
      attr_reader :actual_count

      #: (
      #|   ?String?,
      #|   exec_field: GraphQL::BreadthExec::Executor::ExecutionField[untyped],
      #|   expected_count: Integer,
      #|   actual_count: Integer,
      #| ) -> void
      def initialize(message = nil, exec_field:, expected_count:, actual_count:)
        @exec_field = exec_field
        @expected_count = expected_count
        @actual_count = actual_count
        base = "Incorrect number of results for field `#{exec_field.path.join(".")}`. Expected #{expected_count}, got #{actual_count}."
        super(message ? "#{base} #{message}" : base)
      end
    end

    class UnknownLazyRejectionError < ImplementationError; end
    class LazyStateTransitionError < ImplementationError
      #: (untyped, untyped) -> void
      def initialize(from, to)
        super("Illegal state transition: #{from} -> #{to}")
      end
    end

    class LazySequencingError < ImplementationError
      #: GraphQL::BreadthExec::Executor::LazyElement
      attr_reader :lazy_element

      #: (
      #|   lazy_element: GraphQL::BreadthExec::Executor::LazyElement,
      #|   method_name: String,
      #| ) -> void
      def initialize(lazy_element:, method_name:)
        @lazy_element = lazy_element
        super("The `#{method_name}` method can only be called in planning hooks and their chained callbacks. Called from `#{lazy_element.path}`")
      end
    end

    UNREPORTED_ERROR = ExecutionError.new("__UNREPORTED_ERROR__").freeze
  end
end
