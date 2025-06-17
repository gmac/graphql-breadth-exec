# frozen_string_literal: true

module GraphQL::Cardinal
  class Executor
    module Coercion
      def coerce_scalar_value(type, value)
        case type.graphql_name
        when "String"
          value.is_a?(String) ? value : value.to_s
        when "ID"
          value.is_a?(String) || value.is_a?(Numeric) ? value : value.to_s
        when "Int"
          value.is_a?(Integer) ? value : Integer(value)
        when "Float"
          value.is_a?(Float) ? value : Float(value)
        when "Boolean"
          value == TrueClass || value == FalseClass ? value : !!value
        else
          value
        end
      end

      def coerce_enum_value(type, value)
        value
      end
    end
  end
end
