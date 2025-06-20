# frozen_string_literal: true

module GraphQL
  module Cardinal
    class FieldResolver
      def authorized?(_ctx)
        true
      end

      def resolve(objects, _args, _ctx, _scope)
        raise NotImplementedError, "Resolver#resolve must be implemented."
      end
    end

    class HashKeyResolver < FieldResolver
      def initialize(key)
        @key = key
      end

      def resolve(objects, _args, _ctx, _scope)
        objects.map do |hash|
          hash[@key]
        rescue StandardError => e
          InternalError.new
        end
      end
    end

    class TypenameResolver < FieldResolver
      def resolve(objects, _args, _ctx, scope)
        typename = scope.parent_type.graphql_name.freeze
        objects.map { typename }
      end
    end
  end
end
