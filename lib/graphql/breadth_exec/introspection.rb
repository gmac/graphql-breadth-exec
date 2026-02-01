# frozen_string_literal: true

module GraphQL
  module BreadthExec
    module Introspection
      module Schema
        class EndpointResolver < FieldResolver
          def resolve(objects, _args, ctx, _exec_field)
            Array.new(objects.length, ctx.query.schema)
          end
        end

        class TypesResolver < FieldResolver
          def resolve(objects, _args, ctx, _exec_field)
            types = ctx.types.all_types
            Array.new(objects.length, types)
          end
        end

        class DirectivesResolver < FieldResolver
          def resolve(objects, _args, ctx, _exec_field)
            directives = ctx.types.directives
            Array.new(objects.length, directives)
          end
        end
      end

      module Type
        class EndpointResolver < FieldResolver
          def resolve(objects, args, ctx, _exec_field)
            type = ctx.query.get_type(args["name"])
            Array.new(objects.length, type)
          end
        end

        class TypeKindResolver < FieldResolver
          def resolve(objects, _args, ctx, _exec_field)
            map_objects(objects) do |type|
              type.kind.name
            end
          end
        end

        class EnumValuesResolver < FieldResolver
          def resolve(objects, args, ctx, _exec_field)
            map_objects(objects) do |type|
              if type.kind.enum?
                enum_values = ctx.types.enum_values(type)
                enum_values = enum_values.reject(&:deprecation_reason) unless args["includeDeprecated"]
                enum_values
              end
            end
          end
        end

        class FieldsResolver < FieldResolver
          def resolve(objects, args, ctx, _exec_field)
            map_objects(objects) do |type|
              if type.kind.fields?
                fields = ctx.types.fields(type)
                fields = fields.reject(&:deprecation_reason) unless args["includeDeprecated"]
                fields
              end
            end
          end
        end

        class InputFieldsResolver < FieldResolver
          def resolve(objects, args, ctx, _exec_field)
            map_objects(objects) do |type|
              if type.kind.input_object?
                fields = ctx.types.arguments(type)
                fields = fields.reject(&:deprecation_reason) unless args["includeDeprecated"]
                fields
              end
            end
          end
        end

        class InterfacesResolver < FieldResolver
          def resolve(objects, args, ctx, _exec_field)
            map_objects(objects) do |type|
              ctx.types.interfaces(type) if type.kind.fields?
            end
          end
        end

        class PossibleTypesResolver < FieldResolver
          def resolve(objects, args, ctx, _exec_field)
            map_objects(objects) do |type|
              ctx.query.possible_types(type) if type.kind.abstract?
            end
          end
        end

        class OfTypeResolver < FieldResolver
          def resolve(objects, args, ctx, _exec_field)
            map_objects(objects) do |type|
              type.of_type if type.kind.wraps?
            end
          end
        end

        class SpecifiedByUrlResolver < FieldResolver
          def resolve(objects, args, ctx, _exec_field)
            map_objects(objects) do |type|
              type.specified_by_url if type.kind.scalar?
            end
          end
        end
      end

      class ArgumentsResolver < FieldResolver
        def resolve(objects, args, ctx, _exec_field)
          map_objects(objects) do |owner|
            owner_args = ctx.types.arguments(owner)
            owner_args = owner_args.reject(&:deprecation_reason) unless args["includeDeprecated"]
            owner_args
          end
        end
      end

      class ArgumentDefaultValueResolver < FieldResolver
        def resolve(objects, args, ctx, _exec_field)
          builder = nil
          printer = nil
          map_objects(objects) do |arg|
            next nil unless arg.default_value?

            builder ||= GraphQL::Language::DocumentFromSchemaDefinition.new(ctx.query.schema, context: ctx)
            printer ||= GraphQL::Language::Printer.new
            printer.print(builder.build_default_value(arg.default_value, arg.type))
          end
        end
      end

      class IsDeprecatedResolver < FieldResolver
        def resolve(objects, args, ctx, _exec_field)
          map_objects(objects) { !!_1.deprecation_reason }
        end
      end

      ENTRYPOINT_RESOLVERS = {
        "__schema" => Schema::EndpointResolver.new,
        "__type" => Type::EndpointResolver.new,
      }.freeze

      TYPE_RESOLVERS = {
        "__Schema" => {
          "description" => MethodResolver.new(:description),
          "directives" => Schema::DirectivesResolver.new,
          "mutationType" => MethodResolver.new(:mutation),
          "queryType" => MethodResolver.new(:query),
          "subscriptionType" => MethodResolver.new(:subscription),
          "types" => Schema::TypesResolver.new,
        },
        "__Type" => {
          "description" => MethodResolver.new(:description),
          "enumValues" => Type::EnumValuesResolver.new,
          "fields" => Type::FieldsResolver.new,
          "inputFields" => Type::InputFieldsResolver.new,
          "interfaces" => Type::InterfacesResolver.new,
          "kind" => Type::TypeKindResolver.new,
          "name" => MethodResolver.new(:graphql_name),
          "ofType" => Type::OfTypeResolver.new,
          "possibleTypes" => Type::PossibleTypesResolver.new,
          "specifiedByURL" => Type::SpecifiedByUrlResolver.new,
        },
        "__Field" => {
          "args" => ArgumentsResolver.new,
          "deprecationReason" => MethodResolver.new(:deprecation_reason),
          "description" => MethodResolver.new(:description),
          "isDeprecated" => IsDeprecatedResolver.new,
          "name" => MethodResolver.new(:graphql_name),
          "type" => MethodResolver.new(:type),
        },
        "__InputValue" => {
          "defaultValue" => ArgumentDefaultValueResolver.new,
          "deprecationReason" => MethodResolver.new(:deprecation_reason),
          "description" => MethodResolver.new(:description),
          "isDeprecated" => IsDeprecatedResolver.new,
          "name" => MethodResolver.new(:graphql_name),
          "type" => MethodResolver.new(:type),
        },
        "__EnumValue" => {
          "deprecationReason" => MethodResolver.new(:deprecation_reason),
          "description" => MethodResolver.new(:description),
          "isDeprecated" => IsDeprecatedResolver.new,
          "name" => MethodResolver.new(:graphql_name),
        },
        "__Directive" => {
          "args" => ArgumentsResolver.new,
          "description" => MethodResolver.new(:description),
          "isRepeatable" => MethodResolver.new(:repeatable?),
          "locations" => MethodResolver.new(:locations),
          "name" => MethodResolver.new(:graphql_name),
        }
      }.freeze
    end
  end
end
