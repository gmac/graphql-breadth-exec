# typed: true
# frozen_string_literal: true

module GraphQL
  module BreadthExec
    class Executor
      class InputFormatter
        #: type input_hash = Hash[String | Symbol, untyped]

        VALUE_CANNOT_BE_NULL = "Expected value to not be null".freeze

        # Maintains a partial state cache for an individual input traversal
        # this would allow many traversals to be parallelized against a shared input cache
        class State
          #: error_path
          attr_reader :path

          #: Array[InputCoercionError]
          attr_reader :coercion_errors

          #: Array[InputValidatorError]
          attr_reader :validator_errors

          #: GraphQL::Language::Nodes::AbstractNode?
          attr_accessor :current_node

          def initialize
            @coercion_errors = EMPTY_ARRAY
            @validator_errors = EMPTY_ARRAY
            @path = EMPTY_ARRAY
          end

          #: (String | Integer) ?{ () -> untyped } -> untyped
          def add_path(segment, &block)
            @path = [] if @path.frozen?
            @path << segment
            return nil unless block_given?

            begin
              yield
            ensure
              @path.pop
            end
          end

          #: (String | InputCoercionError, ?extensions: extensions_hash?) -> Util::NilLike
          def add_coercion_error(err, extensions: nil)
            err = InputCoercionError.new(err, nodes: current_node ? [current_node] : EMPTY_ARRAY, path: @path.dup, extensions:) if err.is_a?(String)
            @coercion_errors = [] if @coercion_errors.frozen?
            @coercion_errors << err
            UNDEFINED
          end

          #: (String | InputValidatorError, ?extensions: extensions_hash?) -> Util::NilLike
          def add_validator_error(err, extensions: nil)
            err = InputValidatorError.new(err, nodes: current_node ? [current_node] : EMPTY_ARRAY, path: @path.dup, extensions:) if err.is_a?(String)
            @validator_errors = [] if @validator_errors.frozen?
            @validator_errors << err
            UNDEFINED
          end

          #: () -> State
          def reset!
            self.current_node = nil
            @coercion_errors.clear unless @coercion_errors.frozen?
            @validator_errors.clear unless @validator_errors.frozen?
            @path.clear unless @path.frozen?
            self
          end
        end

        #: variables_hash
        attr_reader :variables

        #: Hash[String, Array[InputValidatorError]]
        attr_reader :variable_validator_errors

        #: bool
        attr_accessor :symbolize_keys

        #: (GraphQL::Query::Context, ?symbolize_keys: bool) -> void
        def initialize(context, symbolize_keys: true)
          @context = context
          @variables = EMPTY_OBJECT
          @variable_validator_errors = EMPTY_OBJECT
          @symbolize_keys = symbolize_keys
          @default_state = State.new
        end

        #: -> bool
        def symbolize_keys? = @symbolize_keys

        # based on graphql.js typeFromAST
        #: (untyped) -> singleton(GraphQL::Schema::Member)?
        def type_from_ast(node)
          case node
          when GraphQL::Language::Nodes::ListType
            type_from_ast(node.of_type)&.to_list_type
          when GraphQL::Language::Nodes::NonNullType
            type_from_ast(node.of_type)&.to_non_null_type
          else
            @context.types.type(node.name)
          end
        end

        # based on graphql.js coerceVariableValues
        #: (
        #|   Array[GraphQL::Language::Nodes::VariableDefinition] var_nodes,
        #|   input_hash inputs,
        #|   ?state: State,
        #| ) -> variables_hash
        def coerce_variable_values(var_nodes, inputs, state: @default_state.reset!)
          return @variables if var_nodes.empty? && inputs.empty?

          variable_errors = []
          @variables = {}

          var_nodes.each do |var_node|
            # top-level variable name always remains keyed in unmodified string form...
            var_name = var_node.name
            var_type = type_from_ast(var_node.type)
            value = fetch_with_indifferent_access(inputs, var_name)

            # Variable defines a bogus input type? (ie: Object, Interface, or Union)
            if var_type.nil? || !var_type.unwrap.kind.input?
              type_node = var_node.type #: untyped
              type_node = type_node.of_type while type_node.is_a?(GraphQL::Language::Nodes::WrapperType)

              # This should only ever manifest during static validations,
              # which precedes/short-circuits the variable validation pass.
              # This outcome is only included as a redundancy safeguard.
              variable_errors << InputCoercionError.new(
                "#{type_node.name} isn't a valid input type (on $#{var_name})",
                nodes: [var_node],
              )

            elsif value.equal?(UNDEFINED)
              if !var_node.default_value.nil?
                # Calling `value_from_ast` should never error here assuming the document is properly validated
                @variables[var_name] = value_from_ast(var_node.default_value, var_type, state:)
              elsif var_type.non_null?
                variable_errors << InputCoercionError.new(
                  "Variable \"$#{var_name}\" of required type \"#{var_type.to_type_signature}\" was not provided.",
                  nodes: [var_node],
                  extensions: {
                    "value" => nil,
                    "problems" => [{ "path" => [], "explanation" => VALUE_CANNOT_BE_NULL }],
                  },
                )
              end

            elsif value.nil? && var_type.non_null?
              variable_errors << InputCoercionError.new(
                "Variable \"$#{var_name}\" of non-null type \"#{var_type.to_type_signature}\" must not be null.",
                nodes: [var_node],
                extensions: {
                  "value" => nil,
                  "problems" => [{ "path" => [], "explanation" => VALUE_CANNOT_BE_NULL }],
                },
              )

            else
              # Coerce the provided value into the named variable field, and collect any value coercion errors.
              state.current_node = var_node
              @variables[var_name] = coerce_input_value(value, var_type, state:)
            end
          rescue InputCoercionError => e
            state.add_coercion_error(e)
          ensure
            unless state.coercion_errors.empty?
              message = "Variable $#{var_name} of type #{var_type&.to_type_signature} was provided invalid value"

              unless state.coercion_errors.first.path.empty?
                error_descs = state.coercion_errors.map { "#{_1.path.join(".")} (#{_1.message.sub(/\.$/, "")})" }
                message << " for #{error_descs.join(", ")}"
              end

              extensions = state.coercion_errors.each_with_object({}) { |obj, ext| ext.merge!(obj.extensions) if obj.extensions }
              extensions["value"] = value
              extensions["problems"] = state.coercion_errors.map { { "path" => _1.path, "explanation" => _1.message } }

              variable_errors << InputCoercionError.new(
                message,
                nodes: [var_node],
                extensions:,
              )
            end

            unless state.validator_errors.empty?
              # variable validator errors get stored for later to be incorporated while coercing arguments
              @variable_validator_errors = {} if @variable_validator_errors.frozen?
              @variable_validator_errors[var_name] = state.validator_errors.dup
            end

            state.reset!
          end

          raise InputValidationErrorSet.new(errors: variable_errors) unless variable_errors.empty?

          @variables.freeze
        end

        # based on graphql.js getVariableValues
        # The "variables" argument assumes the provided variables have already been coerced.
        #: (
        #|   GraphQL::Schema::Field | singleton(GraphQL::Schema::Directive),
        #|   (GraphQL::Language::Nodes::Field | GraphQL::Language::Nodes::Directive)?,
        #|   ?variables: variables_hash,
        #|   ?state: State,
        #| ) -> [graphql_arguments, Array[InputError]]
        def coerce_argument_values(member, node, variables: @variables, state: @default_state.reset!)
          arg_defs = @context.types.arguments(member)
          arg_nodes = node&.arguments || EMPTY_ARRAY
          return [EMPTY_OBJECT, EMPTY_ARRAY] if arg_defs.empty?

          arguments = {}
          argument_errors = []
          arg_nodes_by_name = arg_nodes.each_with_object({}) do |arg_node, acc|
            acc[arg_node.name] = arg_node
          end

          arg_defs.each do |arg|
            arg_node = arg_nodes_by_name[arg.graphql_name]
            arg_key = symbolize_keys? ? arg.keyword : arg.graphql_name
            state.add_path(arg.graphql_name)
            state.current_node = arg_node

            if arg_node.nil?
              if arg.default_value?
                arg_value = format_default_value(arg.default_value, arg.type, state:)
                arguments[arg_key] = validate_value(arg, arg_value, state:)
              elsif arg.type.non_null?
                argument_errors << InputCoercionError.new(
                  "Argument \"#{arg.graphql_name}\" of required type \"#{arg.type.to_type_signature}\" was not provided.",
                  nodes: node ? [node] : EMPTY_ARRAY,
                )
              end

              argument_errors.concat(state.validator_errors)
              next
            end

            value_node = arg_node.value
            is_null = false

            if value_node.is_a?(GraphQL::Language::Nodes::NullValue)
              is_null = true

            elsif value_node.is_a?(GraphQL::Language::Nodes::VariableIdentifier)
              variable_value = (variables || EMPTY_OBJECT).fetch(value_node.name, UNDEFINED)
              if variable_value.equal?(UNDEFINED)
                if arg.default_value?
                  state.current_node = value_node
                  arg_value = format_default_value(arg.default_value, arg.type, state:)
                  arguments[arg_key] = validate_value(arg, arg_value, state:)
                elsif arg.type.non_null?
                  argument_errors << InputCoercionError.new(
                    "Argument \"#{arg.graphql_name}\" of required type \"#{arg.type.to_type_signature}\" " \
                      "was provided the variable \"$#{value_node.name}\" which was not provided a runtime value.",
                    nodes: [value_node],
                  )
                end

                argument_errors.concat(state.validator_errors)
                next
              end

              is_null = variable_value.nil?
            end

            if is_null && arg.type.non_null?
              argument_errors << InputCoercionError.new(
                "Argument \"#{arg.graphql_name}\" of non-null type \"#{arg.type.to_type_signature}\" must not be null.",
                nodes: [value_node],
              )
              next
            end

            arg_value = value_from_ast(value_node, arg.type, variables:, state:)
            if arg_value.equal?(UNDEFINED)
              argument_errors.concat(state.coercion_errors)
              argument_errors.concat(state.validator_errors)
              next
            end

            arguments[arg_key] = validate_value(arg, arg_value, state:)
            argument_errors.concat(state.validator_errors)
          ensure
            state.reset!
          end

          if !argument_errors.empty? && argument_errors.any?(InputCoercionError)
            # If we got here, then GraphQL Ruby passed something that BreadthExec didn't (implies a BreadthExec bug)
            # Report the error rather than raising so that shimmed fields can still use GraphQL Ruby values
            GraphQL::BreadthExec.report_error(InputValidationErrorSet.new(errors: argument_errors.grep(InputCoercionError)))
            arguments = EMPTY_OBJECT
          else
            # otherwise, validate the resolved field argument structure
            validate_value(member, arguments, state:)
            validate_value(member.resolver, arguments, state:, as: member) if member.is_a?(GraphQL::Schema::Field) && member.resolver
            argument_errors.concat(state.validator_errors)
          end

          [arguments.freeze, argument_errors]
        end

        # based on graphql.js coerceInputValue
        #: (
        #|   untyped input_value,
        #|   untyped type,
        #|   ?state: State,
        #| ) -> untyped
        def coerce_input_value(input_value, type, state: State.new)
          if type.non_null?
            if !input_value.nil?
              coerce_input_value(input_value, type.of_type, state:)
            else
              # this check is already covered by the main coerce_variable_values loop
              state.add_coercion_error("Non-null type cannot be null.")
            end

          elsif input_value.nil?
            nil

          elsif type.list?
            item_type = type.of_type

            if input_value.is_a?(Array)
              input_value.map.with_index do |item, index|
                state.add_path(index) { coerce_input_value(item, item_type, state:) }
              end.freeze
            else
              # Lists accept a non-list value as a set of one.
              item_value = state.add_path(0) { coerce_input_value(input_value, item_type, state:) }
              [item_value].freeze
            end

          elsif type.kind.input_object?
            unless input_value.is_a?(Hash)
              return state.add_coercion_error("Expected type \"#{type.graphql_name}\" to be an object.")
            end

            coerced_obj = {}

            arg_defs_by_name = arguments_map_for_type(type)
            arg_defs_by_name.each_value do |arg|
              state.add_path(arg.graphql_name)
              arg_key = symbolize_keys? ? arg.keyword : arg.graphql_name
              arg_value = fetch_with_indifferent_access(input_value, arg.graphql_name)
              if arg_value.equal?(UNDEFINED)
                if arg.default_value?
                  arg_value = format_default_value(arg.default_value, arg.type, state:)
                  coerced_obj[arg_key] = validate_value(arg, arg_value, state:)
                elsif arg.type.non_null?
                  state.add_coercion_error("Field \"#{arg.graphql_name}\" of required type \"#{arg.type.to_type_signature}\" was not provided.")
                end
                next
              end

              arg_value = coerce_input_value(arg_value, arg.type, state:)
              coerced_obj[arg_key] = validate_value(arg, arg_value, state:)
            ensure
              state.path.pop
            end

            if input_value.size > coerced_obj.size
              input_value.each_key do |field_name|
                unless arg_defs_by_name.key?(field_name.to_s)
                  state.add_coercion_error("Field \"#{field_name}\" is not defined by type \"#{type.graphql_name}\".")
                end
              end
            end

            if one_of_input_object?(type)
              if coerced_obj.size != 1
                state.add_coercion_error("Exactly one key must be specified for OneOf type \"#{type.graphql_name}\".")
              end

              coerced_obj.each do |arg_key, value|
                next unless value.nil?

                state.add_coercion_error("Exactly one value must be specified for OneOf type \"#{type.graphql_name}\", but \"#{arg_key}\" was null.")
              end
            end

            validate_value(type, coerced_obj.freeze, state:)
          elsif type.kind.leaf?
            result = begin
              type.coerce_input(input_value, @context)
            rescue GraphQL::ExecutionError, GraphQL::BreadthExec::ExecutionError => e
              return state.add_coercion_error(e.message, extensions: e.extensions)
            rescue StandardError => e
              return state.add_coercion_error("Expected type \"#{type.graphql_name}\".")
            end

            if result.nil?
              if type.kind.enum?
                # variable validation (see test_errors_for_incorrect_variable_enums)
                state.add_coercion_error("Value does not exist in '#{type.graphql_name}' enum.")
              elsif type.default_scalar?
                # variable validation (see test_errors_for_incorrect_variable_values)
                state.add_coercion_error("Cannot represent non-#{type.graphql_name} value.")
              end
            end

            result
          else
            raise InputCoercionError, "Unexpected input type: #{type.graphql_name}."
          end
        end

        # based on graphql.js valueFromAST
        # This method should never raise errors in a validated document,
        # because we know that everything is correct by the AST.
        #: (
        #|   GraphQL::Language::Nodes::AbstractNode? | Array[GraphQL::Language::Nodes::AbstractNode] value_node,
        #|   untyped type,
        #|   ?variables: variables_hash?,
        #|   ?state: State,
        #| ) -> untyped
        def value_from_ast(value_node, type, variables: nil, state: State.new)
          if value_node.nil?
            state.add_coercion_error("Expected value node to be non-null.")

          elsif value_node.is_a?(GraphQL::Language::Nodes::VariableIdentifier)
            var_name = value_node.name
            variable_value = (variables || EMPTY_OBJECT).fetch(var_name, UNDEFINED)
            if variable_value.equal?(UNDEFINED)
              return state.add_coercion_error("Expected variable $#{var_name} to be defined.")
            end

            if variable_value.nil? && type.non_null?
              return state.add_coercion_error("Expected variable $#{var_name} to be non-null.")
            end

            # Add all runtime errors that were cached for this variable field
            @variable_validator_errors.fetch(var_name, EMPTY_ARRAY).each do |e|
              state.add_validator_error(InputValidatorError.new(e.message, nodes: e.nodes.dup, path: state.path + e.path, extensions: e.extensions))
            end

            variable_value
          elsif type.non_null?
            if value_node.is_a?(GraphQL::Language::Nodes::NullValue)
              return state.add_coercion_error("Expected value node to be non-null.")
            end

            value_from_ast(value_node, type.of_type, variables:, state:)
          elsif value_node.is_a?(GraphQL::Language::Nodes::NullValue)
            nil
          elsif type.list?
            item_type = type.of_type

            if value_node.is_a?(Array)
              coerced_items = []
              value_node.each_with_index do |item_node, index|
                item_value = state.add_path(index) do
                  if missing_variable?(item_node, variables)
                    return state.add_coercion_error("Expected item to be non-null.") if item_type.non_null?

                    nil
                  else
                    value_from_ast(item_node, item_type, variables:, state:)
                  end
                end
                return UNDEFINED if item_value.equal?(UNDEFINED)

                coerced_items << item_value
              end
              coerced_items.freeze
            else
              # Lists accept a non-list value as a set of one.
              item_value = state.add_path(0) { value_from_ast(value_node, item_type, variables:, state:) }
              return UNDEFINED if item_value.equal?(UNDEFINED)

              [item_value].freeze
            end

          elsif type.kind.input_object?
            unless value_node.is_a?(GraphQL::Language::Nodes::InputObject)
              return state.add_coercion_error("Expected value node to be an input object.")
            end

            coerced_obj = {}
            arg_nodes_by_name = value_node.arguments.each_with_object({}) do |arg_node, acc|
              acc[arg_node.name] = arg_node
            end

            @context.types.arguments(type).each do |arg|
              arg_node = arg_nodes_by_name[arg.graphql_name]
              arg_key = symbolize_keys? ? arg.keyword : arg.graphql_name
              state.add_path(arg.graphql_name)
              state.current_node = arg_node

              if arg_node.nil? || missing_variable?(arg_node.value, variables)
                if arg.default_value?
                  arg_value = format_default_value(arg.default_value, arg.type, state:)
                  coerced_obj[arg_key] = validate_value(arg, arg_value, state:)
                elsif arg.type.non_null?
                  return state.add_coercion_error("Expected argument \"#{arg.graphql_name}\" to be non-null.")
                end
                next
              end

              arg_value = value_from_ast(arg_node.value, arg.type, variables:, state:)
              return UNDEFINED if arg_value.equal?(UNDEFINED)

              coerced_obj[arg_key] = validate_value(arg, arg_value, state:)
            ensure
              state.path.pop
            end

            if one_of_input_object?(type)
              if coerced_obj.size != 1
                return state.add_coercion_error("Exactly one key must be specified for OneOf type \"#{type.graphql_name}\".")
              end

              coerced_obj.each do |arg_key, value|
                if value.nil?
                  return state.add_coercion_error("Exactly one value must be specified for OneOf type \"#{type.graphql_name}\", but \"#{arg_key}\" was null.")
                end
              end
            end

            validate_value(type, coerced_obj.freeze, state:)
          elsif type.kind.leaf?
            if type.kind.enum?
              if value_node.is_a?(GraphQL::Language::Nodes::Enum)
                value_node = value_node.name
              else
                return state.add_coercion_error("Expected value node to be an enum.")
              end
            end

            result = begin
              type.coerce_input(value_node, @context)
            rescue GraphQL::ExecutionError, GraphQL::BreadthExec::ExecutionError => e
              return state.add_coercion_error(e.message, extensions: e.extensions)
            rescue StandardError => e
              return state.add_coercion_error("Expected type \"#{type.graphql_name}\".")
            end

            # default scalar values (String, Int, Boolean, etc.) cannot be nil
            if result.nil? && type.kind.scalar? && type.default_scalar?
              return state.add_coercion_error("Cannot represent non-#{type.graphql_name} value.")
            end

            result
          else
            raise InputCoercionError, "Unexpected input type: #{type.graphql_name}."
          end
        end

        #: (
        #|   untyped default_value,
        #|   untyped type,
        #|   ?state: State,
        #| ) -> untyped
        def format_default_value(default_value, type, state: State.new)
          return default_value if default_value.nil?

          # Unwrap non-null wrapper since default values don't need null checking
          type = Util.unwrap_non_null(type)

          if type.list?
            if default_value.is_a?(Array)
              default_value.map.with_index do |item, index|
                state.add_path(index) { format_default_value(item, type.of_type, state:) }
              end.freeze
            else
              # Lists accept a non-list value as a set of one.
              item_value = state.add_path(0) { format_default_value(default_value, type.of_type, state:) }
              [item_value].freeze
            end
          elsif type.kind.input_object?
            unless default_value.is_a?(Hash)
              # should never happen in a valid document
              return state.add_coercion_error("Expected default value for type \"#{type.graphql_name}\" to be an object.")
            end

            coerced_obj = {}
            arg_defs_by_name = arguments_map_for_type(type)
            default_value.each do |key, value|
              arg = arg_defs_by_name[key.to_s]
              if arg.nil?
                # should never happen in a valid document
                state.add_coercion_error("Invalid default field \"#{key}\" for type \"#{type.graphql_name}\".")
                next
              end

              state.add_path(arg.graphql_name) do
                arg_key = symbolize_keys? ? arg.keyword : arg.graphql_name
                arg_value = format_default_value(value, arg.type, state:)
                coerced_obj[arg_key] = validate_value(arg, arg_value, state:)
              end
            end

            # don't validate this – it's not a complete value
            coerced_obj.freeze
          else
            default_value
          end
        end

        #: (untyped, untyped, ?state: State, ?as: untyped) -> untyped
        def validate_value(member, value, state: State.new, as: nil)
          unless member.validators.empty?
            member.validators.each do |validator|
              # Always validate statically with no object.
              # BreadthExec does not support object-contextual arguments.
              result = validator.validate(nil, @context, value)
              next if result.nil?

              if result.is_a?(InputValidatorError)
                state.add_validator_error(result)
                next
              end

              next if result.respond_to?(:empty?) && result.empty?

              interpolation_vars = { validated: (as || member).graphql_name, value: value.inspect }

              case result
              when String
                state.add_validator_error(result % interpolation_vars)
              when Array
                result.each do |err|
                  if err.is_a?(InputValidatorError)
                    state.add_validator_error(err)
                  else
                    state.add_validator_error(err % interpolation_vars)
                  end
                end
              else
                raise ImplementationError, "Unexpected argument validation result: #{result.class}."
              end
            end
          end

          value
        end

        private

        #: (input_hash, String, ?default: untyped) -> untyped
        def fetch_with_indifferent_access(input, key, default: UNDEFINED)
          input.fetch(key) { input.fetch(key.to_sym, default) }
        end

        #: (
        #|   GraphQL::Language::Nodes::AbstractNode? | Array[GraphQL::Language::Nodes::AbstractNode] value_node,
        #|   variables_hash? variables,
        #| ) -> bool
        def missing_variable?(value_node, variables)
          if value_node.is_a?(GraphQL::Language::Nodes::VariableIdentifier)
            variables.nil? || !variables.key?(value_node.name)
          else
            false
          end
        end

        #: (singleton(GraphQL::Schema::InputObject)) -> bool
        def one_of_input_object?(type)
          @one_of_types ||= {}.compare_by_identity
          @one_of_types.fetch(type) do
            @one_of_types[type] = !type.directives.empty? && type.directives.any? { _1.graphql_name == "oneOf" }
          end
        end

        #: (GraphQL::Schema::Member type) -> Hash[String, GraphQL::Schema::Argument]
        def arguments_map_for_type(type)
          @arguments_map_by_type ||= {}.compare_by_identity
          @arguments_map_by_type[type] ||= @context.types.arguments(type).each_with_object({}) do |arg, memo|
            memo[arg.graphql_name] = arg
          end
        end
      end
    end
  end
end
