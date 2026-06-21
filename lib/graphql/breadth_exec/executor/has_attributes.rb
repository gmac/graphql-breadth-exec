# typed: true
# frozen_string_literal: true

module GraphQL::BreadthExec
  class Executor
    module HasAttributes
      def initialize(...)
        super(...)
        @attributes = nil
      end

      #: () -> Hash[untyped, untyped]
      def attributes
        @attributes ||= {}
      end

      #: (untyped, ?default: untyped) -> untyped
      def attribute(key, default: nil)
        return default unless @attributes

        @attributes.fetch(key, default)
      end

      #: (untyped) -> bool
      def attribute?(key)
        return false unless @attributes

        @attributes.key?(key)
      end
    end
  end
end
