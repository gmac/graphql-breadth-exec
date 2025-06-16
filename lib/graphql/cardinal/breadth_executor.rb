# frozen_string_literal: true

require_relative "./breadth_executor/execution_scope"
require_relative "./breadth_executor/execution_field"
require_relative "./breadth_executor/authorization"
require_relative "./breadth_executor/tracer"

module GraphQL
  module Cardinal
    class BreadthExecutor
      include Scalars

      attr_reader :exec_count

      def initialize(schema, resolvers, document, root_object)
        @schema = schema
        @resolvers = resolvers
        @document = document
        @root_object = root_object
        @tracer = Tracer.new
        @variables = {}
        @context = {}
        @path = []
        @data = {}
        @errors = []
        @exec_count = 0
        @non_null_violation = false
      end

      def perform
        @query = GraphQL::Query.new(@schema, document: @document) # << for schema reference
        @context[:query] = @query
        operation = @query.selected_operation

        scopes_to_execute = [
          ExecutionScope.new(
            parent_type: @query.root_type_for_operation(operation.operation_type),
            selections: operation.selections,
            sources: [@root_object],
            responses: [@data],
          )
        ]

        # execute until no more scopes without using recursion...
        until scopes_to_execute.empty?
          scopes_to_execute.concat(execute_scope(scopes_to_execute.shift))
        end

        @non_null_violation ? Cardinal::Shaper.perform(@query, @data) : @data
      end

      private

      def execute_scope(exec_scope)
        next_scopes = []
        parent_type = exec_scope.parent_type
        parent_selections = exec_scope.selections
        parent_sources = exec_scope.sources
        parent_responses = exec_scope.responses

        execution_fields_by_key(parent_type, parent_selections).each do |key, exec_field|
          @path.push(key)
          field_name = exec_field.name
          Authorization.can_access_field?(parent_type, field_name, @context)

          wrapped_return_type = @query.get_field(parent_type, field_name).type
          return_type = wrapped_return_type.unwrap
          Authorization.can_access_type?(return_type, @context)

          field_resolver = @resolvers.dig(parent_type.graphql_name, field_name)
          resolved_sources = begin
            @tracer&.before_resolve_field(parent_type, field_name, parent_sources.length, @context)
            field_resolver.call(parent_sources, exec_field.arguments(@variables), @context)
          rescue StandardError => e
            Array.new(parent_sources.length, InternalError.new)
          ensure
            @tracer&.after_resolve_field(parent_type, field_name, parent_sources.length, @context)
            @exec_count += 1
          end

          raise InternalError, "Incorrect results" if resolved_sources.length != parent_sources.length

          if return_type.kind.composite?
            # build results with child selections
            next_sources = []
            next_responses = []
            resolved_sources.each_with_index do |source, i|
              parent_responses[i][key] = build_composite_response(wrapped_return_type, source, next_sources, next_responses)
            end

            if return_type.kind.abstract?
              type_resolver = @resolvers.dig(return_type.graphql_name, "__type__")
              next_sources_by_type = Hash.new { |h, k| h[k] = [] }
              next_responses_by_type = Hash.new { |h, k| h[k] = [] }
              next_sources.each_with_index do |source, i|
                impl_type = type_resolver.call(source, @context)
                next_sources_by_type[impl_type] << source
                next_responses_by_type[impl_type] << next_responses[i]
              end

              next_sources_by_type.each do |impl_type, impl_type_sources|
                # check concrete type access only once per resolved type...
                unless Authorization.can_access_type?(impl_type, @context)
                  impl_type_sources = Array.new(impl_type_sources.length, AuthorizationError.new)
                end

                next_scopes << ExecutionScope.new(
                  parent_type: impl_type,
                  selections: exec_field.selections,
                  sources: impl_type_sources,
                  responses: next_responses_by_type[impl_type],
                )
              end
            else
              next_scopes << ExecutionScope.new(
                parent_type: return_type,
                selections: exec_field.selections,
                sources: next_sources,
                responses: next_responses,
              )
            end
          else
            # build leaf results
            resolved_sources.each_with_index do |val, i|
              parent_responses[i][key] = if val.nil? || val.is_a?(StandardError)
                handle_missing_value(wrapped_return_type, val)
              elsif return_type.kind.scalar?
                coerce_scalar_value(wrapped_return_type, val)
              else
                val
              end
            end
          end

          @path.pop
        end

        next_scopes
      end

      def build_composite_response(wrapped_return_type, source, next_sources, next_responses)
        # if object authorization check implemented, then...
        # unless Authorization.can_access_object?(return_type, source, @context)

        if source.nil? || source.is_a?(StandardError)
          handle_missing_value(wrapped_return_type, source)
        elsif wrapped_return_type.list?
          # error if not array...
          wrapped_return_type = wrapped_return_type.of_type while wrapped_return_type.non_null?

          source.map do |src|
            build_composite_response(wrapped_return_type.of_type, src, next_sources, next_responses)
          end
        else
          next_sources << source
          next_responses << {}
          next_responses.last
        end
      end

      def handle_missing_value(wrapped_return_type, val)
        is_error = !!val
        if is_error
          # do something...?
        end
        if wrapped_return_type.non_null?
          @non_null_violation = true
          # format error if val (error)...
        end
        nil
      end

      def execution_fields_by_key(parent_type, selections, map: Hash.new { |h, k| h[k] = ExecutionField.new })
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
    end
  end
end
