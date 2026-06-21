# typed: true
# frozen_string_literal: true

module GraphQL::BreadthExec
  class Executor
    class ExecutionPlanner
      QUERY_OPERATION = "query".freeze
      MUTATION_OPERATION = "mutation".freeze
      SUBSCRIPTION_OPERATION = "subscription".freeze
      TYPENAME_FIELD = "__typename".freeze
      ENGINE_RUNTIME_DIRECTIVES = ["skip", "include"].freeze

      class << self
        #: (String, GraphQL::Query::Context) -> singleton(GraphQL::Schema::Object)
        def root_type_for_operation(operation_type, context)
          case operation_type
          when QUERY_OPERATION
            context.types.query_root
          when MUTATION_OPERATION
            context.types.mutation_root
          when SUBSCRIPTION_OPERATION
            context.types.subscription_root
          else
            raise ArgumentError, "unexpected root type name: #{operation_type}"
          end
        end
      end

      #: (
      #|   executor: Executor,
      #|   resolvers: Hash[String, Hash[String, resolver]],
      #| ) -> void
      def initialize(executor:, resolvers:)
        @executor = executor
        @resolvers = resolvers
        @schema = @executor.schema
        @context = @executor.context
        @planned_scopes_by_field = {}.compare_by_identity
        @has_runtime_directives = false
      end

      #: (ExecutionField[untyped]) -> ExecutionScope?
      def planned_scope_for(exec_field)
        @planned_scopes_by_field[exec_field]
      end

      #: (String) -> singleton(GraphQL::Schema::Object)
      def root_type_for_operation(operation_type)
        self.class.root_type_for_operation(operation_type, @context)
      end

      #: (GraphQL::Language::Nodes::OperationDefinition) -> Array[ExecutionDirective]
      def root_directives_for_operation(operation)
        operation.directives.map { |node| build_execution_directive(node, depth: 0) }
      end

      #: (
      #|   GraphQL::Language::Nodes::OperationDefinition,
      #|   root_object: untyped,
      #|   result: graphql_result,
      #| ) -> Array[ExecutionScope]
      def root_scopes_for_operation(operation, root_object:, result:)
        case operation.operation_type
        when QUERY_OPERATION
          [
            ExecutionScope.new(
              executor: @executor,
              parent_type: root_type_for_operation(QUERY_OPERATION),
              selections: operation.selections,
              objects: [root_object],
              results: [result],
            ),
          ]
        when MUTATION_OPERATION
          # each mutation field must run serially as its own scope
          mutation_type = root_type_for_operation(MUTATION_OPERATION)
          selections_grouped_by_key(mutation_type, operation.selections).each_value.map do |selections|
            ExecutionScope.new(
              executor: @executor,
              parent_type: mutation_type,
              selections: selections.freeze,
              objects: [root_object],
              results: [result],
            )
          end
        when SUBSCRIPTION_OPERATION
          [
            ExecutionScope.new(
              executor: @executor,
              parent_type: root_type_for_operation(SUBSCRIPTION_OPERATION),
              selections: operation.selections,
              objects: [root_object],
              results: [result],
            ),
          ]
        end
      end

      #: (Array[ExecutionScope]) -> Array[ExecutionScope]
      def plan_scopes(scopes)
        scopes.reject! { _1.objects.empty? }
        scopes.freeze
        return scopes if scopes.empty?

        scopes.each do |exec_scope|
          # invoke planning hooks from bottom-up to bubble configuration...
          build_execution_tree(exec_scope).reverse_each do |exec_field|
            exec_field.resolver.plan(exec_field, @context)
          end
        end

        scopes
      end

      private

      #: (
      #|   singleton(GraphQL::Schema::Member) parent_type,
      #|   Array[selection_node] selections,
      #|   ?map: Hash[String, Array[GraphQL::Language::Nodes::Field]],
      #| ) -> Hash[String, Array[GraphQL::Language::Nodes::Field]]
      def selections_grouped_by_key(parent_type, selections, map: Hash.new { |h, k| h[k] = [] })
        types = @context.types
        selections.each do |node|
          next if node_skipped?(node)

          case node
          when GraphQL::Language::Nodes::Field
            map[(node.alias || node.name).freeze] << node
          when GraphQL::Language::Nodes::InlineFragment
            fragment_type = node.type ? types.type(node.type.name) : parent_type
            if parent_type_possible?(fragment_type, parent_type)
              selections_grouped_by_key(parent_type, node.selections, map: map)
            end
          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @executor.fragments.fetch(node.name)
            fragment_type = types.type(fragment.type.name)
            if parent_type_possible?(fragment_type, parent_type)
              selections_grouped_by_key(parent_type, fragment.selections, map: map)
            end
          else
            raise DocumentError.new("Invalid selection node type")
          end
        end

        map
      end

      #: (selection_node node) -> bool
      def node_skipped?(node)
        return false if node.directives.empty?

        node.directives.any? do |directive|
          if directive.name == "skip"
            if_argument?(directive.arguments.first)
          elsif directive.name == "include"
            !if_argument?(directive.arguments.first)
          else
            @has_runtime_directives = true
            false
          end
        end
      end

      #: (untyped) -> bool
      def if_argument?(bool_arg)
        if bool_arg.value.is_a?(GraphQL::Language::Nodes::VariableIdentifier)
          @executor.variables[bool_arg.value.name] || @executor.variables[bool_arg.value.name.to_sym]
        else
          bool_arg.value
        end
      end

      #: (
      #|   singleton(GraphQL::Schema::Member) fragment_type,
      #|   singleton(GraphQL::Schema::Member) parent_type,
      #| ) -> bool
      def parent_type_possible?(fragment_type, parent_type)
        fragment_type == parent_type || @context.types.possible_types(fragment_type).include?(parent_type)
      end

      #: (
      #|   ExecutionScope,
      #|   ?ordered_fields: Array[ExecutionField[untyped]],
      #| ) -> Array[ExecutionField[untyped]]
      def build_execution_tree(exec_scope, ordered_fields = [])
        @has_runtime_directives = false
        selections_by_key = selections_grouped_by_key(exec_scope.parent_type, exec_scope.selections)
        has_runtime_directives = @has_runtime_directives

        selections_by_key.each do |key, nodes|
          exec_field = build_execution_field(key, nodes, exec_scope, has_runtime_directives)
          add_execution_field_branch(exec_field, ordered_fields)
        end

        exec_scope.fields.freeze
        ordered_fields
      end

      #: (ExecutionField[untyped], Array[ExecutionField[untyped]]) -> void
      def add_execution_field_branch(exec_field, ordered_fields)
        exec_field.scope.fields[exec_field.key] = exec_field
        ordered_fields << exec_field

        return_type = exec_field.type.unwrap
        return if return_type.kind.leaf? || return_type.kind.abstract?

        next_scope = ExecutionScope.new(
          executor: @executor,
          parent_type: return_type,
          parent_field: exec_field,
          selections: exec_field.selections,
          objects: [],
          results: [],
        )
        @planned_scopes_by_field[exec_field] = next_scope
        build_execution_tree(next_scope, ordered_fields)
      end

      #: (
      #|   String key,
      #|   Array[GraphQL::Language::Nodes::Field] nodes,
      #|   ExecutionScope exec_scope,
      #|   ?bool has_runtime_directives,
      #| ) -> ExecutionField[untyped]
      def build_execution_field(key, nodes, exec_scope, has_runtime_directives = false)
        first_node = nodes.first
        node_name = first_node.name

        definition = @context.types.field(exec_scope.parent_type, node_name)
        resolver = if definition.is_a?(HasBreadthResolver::Field) && definition.breadth_resolver
          definition.breadth_resolver
        elsif definition.introspection?
          if definition.graphql_name == TYPENAME_FIELD
            Introspection::TYPENAME_RESOLVER
          elsif exec_scope.parent_type.equal?(@context.types.query_root)
            Introspection::ENTRYPOINT_RESOLVERS.dig(definition.graphql_name)
          else
            Introspection::TYPE_RESOLVERS.dig(exec_scope.parent_type.graphql_name, definition.graphql_name)
          end
        else
          @resolvers.dig(exec_scope.parent_type.graphql_name, definition.graphql_name)
        end

        unless resolver
          raise NotImplementedError, "No field resolver for '#{exec_scope.parent_type.graphql_name}.#{definition.graphql_name}'"
        end

        directives = exec_scope.parent_field&.directives || EMPTY_ARRAY
        if has_runtime_directives
          nodes.each do |node|
            node.directives.each do |directive|
              next if ENGINE_RUNTIME_DIRECTIVES.include?(directive.name)

              directives = directives.dup if directives.frozen?
              directives << build_execution_directive(directive, depth: exec_scope.depth + 1)
            end
          end
          directives.freeze
        end

        ExecutionField.new(
          key,
          nodes: nodes,
          scope: exec_scope,
          definition: definition,
          resolver: resolver,
          directives: directives,
        )
      end

      #: (GraphQL::Language::Nodes::Directive, ?depth: Integer) -> ExecutionDirective
      def build_execution_directive(node, depth: 0)
        definition = @schema.directives[node.name]
        raise DocumentError.new("No directive definition for '@#{node.name}'") unless definition

        resolver = if definition.respond_to?(:breadth_resolver) && definition.breadth_resolver
          definition.breadth_resolver
        else
          @resolvers["@#{definition.graphql_name}"]
        end
        ExecutionDirective.build(
          executor: @executor,
          node: node,
          definition: definition,
          resolver: resolver,
          depth: depth,
        )
      end
    end
  end
end
