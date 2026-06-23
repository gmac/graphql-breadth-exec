# frozen_string_literal: true

module GraphQL
  module Breadth
    module Introspection
      module Schema
        class EndpointResolver < FieldResolver
          def resolve(exec_field, ctx)
            exec_field.resolve_all(ctx.schema)
          end
        end

        class TypesResolver < FieldResolver
          def resolve(exec_field, ctx)
            exec_field.resolve_all(ctx.types.all_types)
          end
        end

        class DirectivesResolver < FieldResolver
          def resolve(exec_field, ctx)
            exec_field.resolve_all(ctx.types.directives)
          end
        end
      end

      module Type
        class EndpointResolver < FieldResolver
          def resolve(exec_field, ctx)
            exec_field.resolve_all(ctx.types.type(exec_field.arguments[:name]))
          end
        end

        class TypeKindResolver < FieldResolver
          def resolve(exec_field, _ctx)
            exec_field.map_objects { |type| type.kind.name }
          end
        end

        class EnumValuesResolver < FieldResolver
          def resolve(exec_field, ctx)
            exec_field.map_objects do |type|
              next unless type.kind.enum?

              values = ctx.types.enum_values(type)
              exec_field.arguments[:include_deprecated] ? values : values.reject(&:deprecation_reason)
            end
          end
        end

        class FieldsResolver < FieldResolver
          def resolve(exec_field, ctx)
            exec_field.map_objects do |type|
              next unless type.kind.fields?

              fields = ctx.types.fields(type)
              exec_field.arguments[:include_deprecated] ? fields : fields.reject(&:deprecation_reason)
            end
          end
        end

        class InputFieldsResolver < FieldResolver
          def resolve(exec_field, ctx)
            exec_field.map_objects do |type|
              next unless type.kind.input_object?

              fields = ctx.types.arguments(type)
              exec_field.arguments[:include_deprecated] ? fields : fields.reject(&:deprecation_reason)
            end
          end
        end

        class InterfacesResolver < FieldResolver
          def resolve(exec_field, ctx)
            exec_field.map_objects { |type| ctx.types.interfaces(type) if type.kind.fields? }
          end
        end

        class PossibleTypesResolver < FieldResolver
          def resolve(exec_field, ctx)
            exec_field.map_objects { |type| ctx.types.possible_types(type) if type.kind.abstract? }
          end
        end

        class OfTypeResolver < FieldResolver
          def resolve(exec_field, _ctx)
            exec_field.map_objects { |type| type.of_type if type.kind.wraps? }
          end
        end

        class SpecifiedByUrlResolver < FieldResolver
          def resolve(exec_field, _ctx)
            exec_field.map_objects { |type| type.specified_by_url if type.kind.scalar? }
          end
        end
      end

      class ArgumentsResolver < FieldResolver
        def resolve(exec_field, ctx)
          exec_field.map_objects do |owner|
            args = ctx.types.arguments(owner)
            exec_field.arguments[:include_deprecated] ? args : args.reject(&:deprecation_reason)
          end
        end
      end

      class ArgumentDefaultValueResolver < FieldResolver
        def resolve(exec_field, ctx)
          builder = nil
          printer = nil
          exec_field.map_objects do |arg|
            next nil unless arg.default_value?

            builder ||= GraphQL::Language::DocumentFromSchemaDefinition.new(ctx.schema, context: ctx)
            printer ||= GraphQL::Language::Printer.new
            printer.print(builder.build_default_value(arg.default_value, arg.type))
          end
        end
      end

      class IsDeprecatedResolver < FieldResolver
        def resolve(exec_field, _ctx)
          exec_field.map_objects { !!_1.deprecation_reason }
        end
      end

      class TypenameResolver < FieldResolver
        def resolve(exec_field, _ctx)
          exec_field.resolve_all(exec_field.scope.parent_type.graphql_name)
        end
      end

      TYPENAME_RESOLVER = TypenameResolver.new

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
        },
      }.freeze
    end
  end
end
