# frozen_string_literal: true

require "graphql"

module GraphQL
  module Cardinal
    class ExecutionError < StandardError
      attr_accessor :path

      def initialize(message = "An unknown error occurred", path: nil)
        super(message)
        @path = path
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

      def initialize(message = nil, type_name: nil, field_name: nil, path: nil)
        super(message, path: path)
        @type_name = type_name
        @field_name = field_name
      end
    end

    class InvalidNullError < ExecutionError
      attr_reader :original_error

      def initialize(message = "Cannot resolve value", path: nil, original_error: nil)
        super(message, path: path)
        @original_error = original_error
      end
    end

    class InternalError < ExecutionError; end
    class DocumentError < StandardError; end
  end
end
