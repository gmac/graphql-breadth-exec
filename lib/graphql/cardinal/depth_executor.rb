# frozen_string_literal: true

module GraphQL
  module Cardinal
    class DepthExecutor
      attr_reader :exec_count

      def initialize(schema, resolvers, document, root_object)
        @schema = schema
        @resolvers = resolvers
        @document = document
        @root_object = root_object
        @data = {}
        @exec_count = 0
      end

      def perform
        @query = GraphQL::Query.new(@schema, document: @document) # << for schema reference
        operation = @query.selected_operation
        parent_type = @query.root_type_for_operation(operation.operation_type)
        exec_object_scope(parent_type, operation.selections, @root_object, @data, path: [])
        @data
      end

      private

      def exec_object_scope(parent_type, selections, source, response, path:)
        selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            field = @query.get_field(parent_type, node.name)
            field_type = field.type.unwrap
            field_key = node.alias || node.name
            path.push(field_key)

            resolved_source = @resolvers.dig(parent_type.graphql_name, node.name).call(source)
            @exec_count += 1

            puts "#{parent_type.graphql_name}.#{node.name}"
            puts resolved_source

            if field_type.kind.leaf?
              response[field_key] = resolved_source
            elsif field_type.list?
              next_response = Array.new({}, resolved_source.size)
              exec_list_scope(parent_type, node.selections, resolved_source, next_response, path: path)
            else
              exec_object_scope(field_type, node.selections, resolved_source, {}, path: path)
            end
            path.pop

          when GraphQL::Language::Nodes::InlineFragment
            fragment_type = node.type ? @query.get_type(node.type.name) : parent_type
            exec_object_scope(fragment_type, node.selections, source, response, path: path)

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @query.fragments[node.name]
            fragment_type = @query.get_type(fragment.type.name)
            exec_object_scope(fragment_type, node.selections, source, response, path: path)

          else
            raise DocumentError.new("selection node type")
          end
        end
      end

      def exec_list_scope(parent_type, selections, source, response, path:)
        list_type = list_type.of_type while list_type.non_null?
        next_type = list_type.of_type

        list_response = []
        source.each do |src|
          if next_type.list?
            list_response << build_list_response(next_type, src, next_sources, next_responses)
          else
            next_sources << src
            next_responses << {}
            list_response << next_responses.last
          end
        end
        list_response
      end
    end
  end
end
