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

      def map_sources(objects)
        objects.map do |obj|
          yield(obj)
        rescue StandardError => e
          handle_positional_error(e, obj)
        end
      end

      def handle_positional_error(_err, _obj)
        InternalError.new
      end
    end

    class HashKeyResolver < FieldResolver
      def initialize(key)
        @key = key
      end

      def resolve(objects, _args, _ctx, _scope)
        map_sources(objects) do |hash|
          hash[@key]
        end
      end
    end

    class TypenameResolver < FieldResolver
      def resolve(objects, _args, _ctx, scope)
        typename = scope.parent_type.graphql_name.freeze
        map_sources(objects) { typename }
      end
    end
  end
end
