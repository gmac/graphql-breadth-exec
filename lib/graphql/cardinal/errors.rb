# frozen_string_literal: true

require "graphql"

module GraphQL
  module Cardinal
    class ExecutionError < StandardError
      attr_reader :path

      def initialize(message = "An unknown error occurred", path: nil, base: false)
        super(message)
        @path = path
        @base = base
      end

      def base_error?
        @base
      end

      def replace_path(new_path)
        @path = new_path
      end

      def to_h
        {
          "message" => message,
          "path" => path,
        }
      end
    end

    class AuthorizationError < ExecutionError
      attr_reader :type_name, :field_name

      def initialize(message = "Not authorized", type_name: nil, field_name: nil, path: nil, base: true)
        super(message, path: path, base: base)
        @type_name = type_name
        @field_name = field_name
      end
    end

    class InvalidNullError < ExecutionError
      def initialize(message = "Failed to resolve expected value", path: nil)
        super(message, path: path)
      end
    end

    class InternalError < ExecutionError; end
    class InvalidInputError < StandardError; end
    class DocumentError < StandardError; end
  end
end
