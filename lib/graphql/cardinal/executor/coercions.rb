# frozen_string_literal: true

module GraphQL::Cardinal
  class Executor
    module Coercions
      UNDEFINED = Object.new

      def type_from_ast(query, node)
        case node
        when GraphQL::Language::Nodes::ListType
          type_from_ast(query, node.of_type).to_list_type
        when GraphQL::Language::Nodes::NonNullType
          type_from_ast(query, node.of_type).to_non_null_type
        else
          query.get_type(node.name)
        end
      end

      def coerce_variable_values(query, var_nodes, inputs)
        coerced_values = {}

        var_nodes.each do |var_node|
          var_name = var_node.name
          var_type = type_from_ast(query, var_node.type)
          named_type = var_type.unwrap
          
          if !named_type.kind.input?
            raise InvalidInputError

          elsif inputs.key?(var_name)
            value = inputs[var_name]
            raise InvalidInputError if value.nil? && var_type.non_null?

            coerced_values[var_name] = coerce_input_value(query, value, var_type)

          elsif var_node.default_value
            value = value_from_ast(query, var_node.default_value, var_type)
            coerced_values[var_name] = value unless value == UNDEFINED

          elsif var_type.non_null?
            raise InvalidInputError
          end
        end

        coerced_values
      end

      def value_from_ast(query, value_node, type, variables = nil)
        if value_node.nil?
          return UNDEFINED

        elsif value_node.is_a?(GraphQL::Language::Nodes::VariableIdentifier)
          variable_name = value_node.name
          return UNDEFINED if variables.nil? || !variables.key?(variable_name)

          variable_value = variables[variable_name]
          return variable_value.nil? && type.non_null? ? UNDEFINED : variable_value
        
        elsif type.non_null?
          return value_node.is_a?(GraphQL::Language::Nodes::NullValue) ?
            UNDEFINED : value_from_ast(query, value_node, type.of_type, variables)
        
        elsif value_node.is_a?(GraphQL::Language::Nodes::NullValue)
          return nil

        elsif type.list?
          item_type = type.of_type

          if value_node.is_a?(GraphQL::Language::Nodes::ListType)
            coerced_values = []

            value_node.values.each do |item_node|
              if missing_variable?(item_node, variables)
                return UNDEFINED if item_type.non_null?
                coerced_values << nil
              else
                item_value = value_from_ast(query, item_node, item_type, variables)
                return UNDEFINED if item_value == UNDEFINED
                coerced_values << item_value
              end
            end

            return coerced_values
          end

          coerced_value = value_from_ast(query, value_node, item_type, variables)
          return coerced_value == UNDEFINED ? UNDEFINED : [coerced_value]

        elsif type.kind.input_object?
          return UNDEFINED unless value_node.is_a?(GraphQL::Language::Nodes::InputObject)

          coerced_obj = {}
          arg_nodes_by_name = value_node.arguments.each_with_object({}) do |arg_node, acc|
            acc[arg_node.name] = arg_node
          end

          query.types.arguments(type).each do |arg|
            arg_node = arg_nodes_by_name[arg.name]

            if arg_node.nil? || missing_variable?(arg_node.value, variables)
              if !arg.default_value.nil?
                coerced_obj[arg.name] = arg.default_value
              elsif arg.type.non_null?
                return UNDEFINED
              end
              next
            end

            field_value = value_from_ast(query, arg_node.value, arg.type, variables)
            return UNDEFINED if field_value == UNDEFINED

            coerced_obj[arg.name] = field_value
          end

          return coerced_obj

        elsif type.kind.leaf?
          begin
            type.coerce_input(value_node, query.context)
          rescue
            return UNDEFINED
          end

        else
          raise InvalidInputError, "Unexpected input type: #{type.inspect}"
        end
      end

      def missing_variable?(value_node, variables)
        value_node.is_a?(GraphQL::Language::Nodes::VariableIdentifier) && 
          (variables.nil? || !variables.key?(value_node.name))
      end

      def coerce_input_value(query, input_value, type)
        if type.non_null?
          if !input_value.nil?
            coerce_input_value(query, input_value, type.of_type)
          else
            raise InvalidInputError, "Expected non-nullable type \"#{type}\" not to be null."
          end
        
        elsif input_value.nil?
          nil

        elsif type.list?
          item_type = type.of_type

          if input_value.is_a?(Enumerable)
            input_value.each_with_index.map do |item, index|
              coerce_input_value(query, item, item_type)
            end
          else
            [coerce_input_value(query, input_value, item_type)]
          end
        
        elsif type.input_object?
          unless input_value.is_a?(Hash)
            raise InvalidInputError, "Expected type \"#{type.graphql_name}\" to be an object."
          end

          coerced_value = {}
          arg_defs_by_name = query.types.arguments(type).each_with_object({}) do |arg, acc|
            acc[arg.name] = arg
          end

          arg_defs_by_name.each_value do |arg|
            if input_value.key?(arg.name)
              coerced_value[arg.name] = coerce_input_value(query, input_value[name], arg.type)
            elsif !arg.default_value?
              coerced_value[arg.name] = arg.default_value
            elsif arg.type.non_null?
              raise InvalidInputError, "Field \"#{arg.name}\" of required type \"#{arg.type}\" was not provided."
            end
          end

          input_value.each_key do |field_name|
            unless arg_defs_by_name.key?(field_name)
              raise InvalidInputError, "Field \"#{field_name}\" is not defined by type \"#{type.graphql_name}\"."
            end
          end

          coerced_value
        
        elsif type.leaf?
          begin
            result = type.coerce_input(input_value, query.context)
            raise InvalidInputError, "Expected type \"#{type.graphql_name}\"." if result.nil?

            result
          rescue => e
            raise InvalidInputError, "Expected type \"#{type.graphql_name}\". #{e.message}"
          end

        else
          raise InvalidInputError, "Unexpected input type: #{type.inspect}"
        end
      end

      def get_argument_values(query, field_def, node, variables = nil)
        coerced_values = {}
        arg_nodes_by_name = node.arguments.each_with_object({}) do |arg_node, acc|
          acc[arg_node.name] = arg_node
        end

        query.types.arguments(field_def).each do |arg|
          arg_node = arg_nodes_by_name[arg.name]

          if arg_node.nil?
            if !arg.default_value.nil?
              coerced_values[arg.name] = arg.default_value
            elsif arg.type.non_null?
              raise InvalidInputError
            end
            next
          end

          value_node = arg_node.value
          is_null = value_node.is_a?(GraphQL::Language::Nodes::NullValue)

          if value_node.is_a?(GraphQL::Language::Nodes::VariableIdentifier)
            if variables.nil? || !variables.key?(value_node.name)
              if arg.default_value?
                coerced_values[arg.name] = arg.default_value
              elsif arg.type.non_null?
                raise InvalidInputError
              end
              next
            end

            is_null = variables[value_node.name].nil?
          end

          raise InvalidInputError if is_null && arg.type.non_null?

          coerced_value = value_from_ast(query, value_node, arg.type, variables)
          raise InvalidInputError if coerced_value == UNDEFINED

          coerced_values[arg.name] = coerced_value
        end

        coerced_values
      end
    end
  end
end
