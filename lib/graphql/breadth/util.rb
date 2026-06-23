# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    class Util
      class << self
        #: (untyped value, ?stringify_keys: bool) -> untyped
        def deep_copy(value, stringify_keys: false)
          case value
          when Array
            value.map { |v| deep_copy(v, stringify_keys:) }
          when Hash
            value.each_with_object({}) do |(key, val), memo|
              memo[stringify_keys ? key.to_s : key] = deep_copy(val, stringify_keys:)
            end
          else
            value
          end
        end

        #: (untyped) -> untyped
        def unwrap_non_null(current_type)
          current_type = current_type.of_type while current_type.non_null?
          current_type
        end
      end

      class NilLike < BasicObject
        def initialize(identity)
          @identity = identity
        end

        def class = ::GraphQL::Breadth::Util::NilLike
        def is_a?(type) = type === self
        def nil? = true
        def ! = true
        def to_s = ""
        def to_a = []
        def to_h = {}
        def to_i = 0
        def to_f = 0.0
        def to_json(...) = "null"
        def inspect = @identity
      end
    end
  end
end
