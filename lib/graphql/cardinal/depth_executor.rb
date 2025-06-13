# frozen_string_literal: true

module GraphQL
  module Cardinal
    class DepthExecutor
      include Scalars

      attr_reader :exec_count

      def initialize(schema, resolvers, document, root_object)
        @schema = schema
        @resolvers = resolvers
        @document = document
        @root_object = root_object
        @exec_count = 0
      end

      def perform
        @query = GraphQL::Query.new(@schema, document: @document) # << for schema reference
        operation = @query.selected_operation
        parent_type = @query.root_type_for_operation(operation.operation_type)
        exec_object_scope(parent_type, operation.selections, @root_object, path: [])
      end

      private

      def exec_object_scope(parent_type, selections, source, path:, response: nil)
        response ||= {}
        selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            node_type = @query.get_field(parent_type, node.name).type
            named_type = node_type.unwrap
            field_name = node.alias || node.name
            path.push(field_name)

            resolved_source = @resolvers.dig(parent_type.graphql_name, node.name).call(source)
            @exec_count += 1

            response[field_name] = if node_type.list?
              node_type = node_type.of_type while node_type.non_null?
              exec_list_scope(node_type, node.selections, resolved_source, path: path)
            elsif named_type.kind.leaf?
              if !resolved_source.nil? && named_type.kind.scalar?
                coerce_scalar_value(named_type, resolved_source)
              else
                resolved_source
              end
            else
              exec_object_scope(named_type, node.selections, resolved_source, path: path)
            end
            path.pop

          when GraphQL::Language::Nodes::InlineFragment
            fragment_type = node.type ? @query.get_type(node.type.name) : parent_type
            exec_object_scope(fragment_type, node.selections, source, path: path, response: response)

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @query.fragments[node.name]
            fragment_type = @query.get_type(fragment.type.name)
            exec_object_scope(fragment_type, node.selections, source, path: path, response: response)

          else
            raise DocumentError.new("selection node type")
          end
        end

        response
      end

      def exec_list_scope(parent_type, selections, sources, path:)
        parent_type = parent_type.of_type while parent_type.non_null?
        next_node_type = parent_type.of_type
        named_type = parent_type.unwrap

        sources.map.with_index do |src, i|
          path.push(i)
          result = if next_node_type.list?
            resolve_list_scope(next_node_type, selections, src, path: path)
          elsif named_type.kind.leaf?
            src
          else
            exec_object_scope(named_type, selections, src, path: path)
          end
          path.pop
          result
        end
      end
    end
  end
end
