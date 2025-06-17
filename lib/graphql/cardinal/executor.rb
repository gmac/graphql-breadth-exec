# frozen_string_literal: true

require_relative "./executor/execution_scope"
require_relative "./executor/execution_field"
require_relative "./executor/authorization"
require_relative "./executor/tracer"
require_relative "./executor/coercion"
require_relative "./executor/response_hash"
require_relative "./executor/response_shape"

module GraphQL
  module Cardinal
    class Executor
      include Coercion
      include ResponseShape

      TYPENAME_FIELD = "__typename"

      attr_reader :exec_count

      def initialize(schema, resolvers, document, root_object)
        @schema = schema
        @resolvers = resolvers
        @document = document
        @root_object = root_object
        @tracer = Tracer.new
        @variables = {}
        @context = {}
        @data = {}
        @errors = []
        @inline_errors = false
        @path = []
        @exec_queue = []
        @exec_count = 0
        @non_null_violation = false
      end

      def perform
        @query = GraphQL::Query.new(@schema, document: @document) # << for schema reference
        @context[:query] = @query
        operation = @query.selected_operation

        root_scopes = case operation.operation_type
        when "query"
          # query fields can run in parallel
          [
            ExecutionScope.new(
              parent_type: @query.root_type_for_operation(operation.operation_type),
              selections: operation.selections,
              sources: [@root_object],
              responses: [@data],
            )
          ]
        when "mutation"
          # each mutation field must run serially as its own scope
          mutation_type = @query.root_type_for_operation(operation.operation_type)
          execution_fields_by_key(mutation_type, operation.selections).each_value.map do |exec_field|
            ExecutionScope.new(
              parent_type: mutation_type,
              selections: exec_field.nodes,
              sources: [@root_object],
              responses: [@data],
            )
          end
        else
          raise DocumentError.new("Unsupported operation type: #{operation.operation_type}")
        end

        root_scopes.each do |scope|
          @exec_queue << scope
          # execute until no more scopes (without using recursion)...
          execute_scope(@exec_queue.shift) until @exec_queue.empty?
        end

        response = {
          "data" => @inline_errors ? shape_response(@data) : @data,
        }
        response["errors"] = @errors.map(&:to_h) unless @errors.empty?
        response
      end

      private

      def execute_scope(exec_scope)
        lazy_execution_fields = []
        execution_fields_by_key(exec_scope.parent_type, exec_scope.selections).each_value do |exec_field|
          @path.push(exec_field.key)
          parent_type = exec_scope.parent_type
          parent_sources = exec_scope.sources
          field_name = exec_field.name

          exec_field.type = @query.get_field(parent_type, field_name).type
          value_type = exec_field.type.unwrap

          field_resolver = @resolvers.dig(parent_type.graphql_name, field_name)
          unless field_resolver
            raise NotImplementedError, "No field resolver for `#{parent_type.graphql_name}.#{field_name}`"
          end

          resolved_sources = if !field_resolver.authorized?(@context)
            @errors << AuthorizationError.new(type_name: parent_type.graphql_name, field_name: field_name, path: @path.dup)
            Array.new(parent_sources.length, nil)
          elsif !Authorization.can_access_type?(value_type, @context)
            @errors << AuthorizationError.new(type_name: value_type.graphql_name, path: @path.dup)
            Array.new(parent_sources.length, nil)
          else
            begin
              @tracer&.before_resolve_field(parent_type, field_name, parent_sources.length, @context)
              field_resolver.resolve(parent_sources, exec_field.arguments(@variables), @context, exec_scope)
            rescue StandardError => e
              report_exception(e.message)
              @errors << InternalError.new(e.message, path: @path.dup)
              Array.new(parent_sources.length, nil)
            ensure
              @tracer&.after_resolve_field(parent_type, field_name, parent_sources.length, @context)
              @exec_count += 1
            end
          end

          if resolved_sources.is_a?(Promise)
            resolved_sources.source = exec_field
            lazy_execution_fields << resolved_sources
          else
            resolve_execution_field(exec_scope, exec_field, resolved_sources)
          end
          @path.pop
        end

        # --- RUN LAZY CALLBACKS!!

        lazy_execution_fields.each do |promise|
          exec_field = promise.source
          @path.push(exec_field.key)
          resolve_execution_field(exec_scope, exec_field, promise.value)
          @path.pop
        end

        nil
      end

      def resolve_execution_field(exec_scope, exec_field, resolved_sources)
        parent_sources = exec_scope.sources
        parent_responses = exec_scope.responses
        field_key = exec_field.key
        field_name = exec_field.name
        field_type = exec_field.type
        return_type = field_type.unwrap

        if resolved_sources.length != parent_sources.length
          report_exception("Incorrect number of results resolved. Expected #{parent_sources.length}, got #{resolved_sources.length}")
          resolved_sources = Array.new(parent_sources.length, nil)
        end

        if return_type.kind.composite?
          # build results with child selections
          next_sources = []
          next_responses = []
          resolved_sources.each_with_index do |source, i|
            parent_responses[i][field_key] = build_composite_response(field_type, source, next_sources, next_responses)
          end

          if return_type.kind.abstract?
            type_resolver = @resolvers.dig(return_type.graphql_name, "__type__")
            unless type_resolver
              raise NotImplementedError, "No type resolver for `#{return_type.graphql_name}`"
            end

            next_sources_by_type = Hash.new { |h, k| h[k] = [] }
            next_responses_by_type = Hash.new { |h, k| h[k] = [] }
            next_sources.each_with_index do |source, i|
              impl_type = type_resolver.call(source, @context)
              next_sources_by_type[impl_type] << (field_name == TYPENAME_FIELD ? impl_type.graphql_name : source)
              next_responses_by_type[impl_type] << next_responses[i].tap { |r| r.typename = impl_type.graphql_name }
            end

            next_sources_by_type.each do |impl_type, impl_type_sources|
              # check concrete type access only once per resolved type...
              unless Authorization.can_access_type?(impl_type, @context)
                @errors << AuthorizationError.new(type_name: impl_type.graphql_name, path: @path.dup)
                impl_type_sources = Array.new(impl_type_sources.length, AuthorizationError.new(path: @path.dup))
              end

              @exec_queue << ExecutionScope.new(
                parent_type: impl_type,
                selections: exec_field.selections,
                sources: impl_type_sources,
                responses: next_responses_by_type[impl_type],
                parent: exec_scope,
              )
            end
          else
            @exec_queue << ExecutionScope.new(
              parent_type: return_type,
              selections: exec_field.selections,
              sources: next_sources,
              responses: next_responses,
              parent: exec_scope,
            )
          end
        else
          # build leaf results
          resolved_sources.each_with_index do |val, i|
            parent_responses[i][field_key] = if val.nil? || val.is_a?(StandardError)
              build_missing_value(field_type, val)
            elsif return_type.kind.scalar?
              coerce_scalar_value(return_type, val)
            elsif return_type.kind.enum?
              coerce_enum_value(return_type, val)
            else
              val
            end
          end
        end
      end

      def build_composite_response(field_type, source, next_sources, next_responses)
        # if object authorization check implemented, then...
        # unless Authorization.can_access_object?(return_type, source, @context)

        if source.nil? || source.is_a?(ExecutionError)
          build_missing_value(field_type, source)
        elsif field_type.list?
          unless source.is_a?(Array)
            report_exception("Incorrect result for list field. Expected Array, got #{source.class}")
            return build_missing_value(field_type, nil)
          end

          field_type = field_type.of_type while field_type.non_null?

          source.map do |src|
            build_composite_response(field_type.of_type, src, next_sources, next_responses)
          end
        else
          next_sources << source
          next_responses << ResponseHash.new
          next_responses.last
        end
      end

      def build_missing_value(field_type, val)
        if field_type.non_null?
          # upgrade nil in non-null positions to an error
          val = InvalidNullError.new(path: @path.dup, original_error: val)
        end

        if val
          # assure all errors have paths, and note inline error additions
          val = val.path ? val : ExecutionError.new(val.message, path: @path.dup)
          @inline_errors = true
        end

        val
      end

      def execution_fields_by_key(parent_type, selections, map: Hash.new { |h, k| h[k] = ExecutionField.new(k) })
        selections.each do |node|
          next if node_skipped?(node)

          case node
          when GraphQL::Language::Nodes::Field
            map[node.alias || node.name].add_node(node)
          when GraphQL::Language::Nodes::InlineFragment
            fragment_type = node.type ? @query.get_type(node.type.name) : parent_type
            if @query.possible_types(fragment_type).include?(parent_type)
              execution_fields_by_key(parent_type, node.selections, map: map)
            end

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @query.fragments[node.name]
            fragment_type = @query.get_type(fragment.type.name)
            if @query.possible_types(fragment_type).include?(parent_type)
              execution_fields_by_key(parent_type, node.selections, map: map)
            end

          else
            raise DocumentError.new("selection node type")
          end
        end
        map
      end

      def node_skipped?(node)
        return false if node.directives.empty?

        node.directives.any? do |directive|
          if directive.name == "skip"
            if_argument?(directive.arguments.first)
          elsif directive.name == "include"
            !if_argument?(directive.arguments.first)
          else
            false
          end
        end
      end

      def if_argument?(bool_arg)
        if bool_arg.value.is_a?(GraphQL::Language::Nodes::VariableIdentifier)
          @variables[bool_arg.value.name] || @variables[bool_arg.value.name.to_sym]
        else
          bool_arg.value
        end
      end

      def report_exception(message, path: @path.dup)
        # todo: hook up some kind of error reporting...
      end
    end

    class BreadthExecutor < Executor; end
  end
end
