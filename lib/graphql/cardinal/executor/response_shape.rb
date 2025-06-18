# typed: false
# frozen_string_literal: true

module GraphQL::Cardinal
  class Executor
    module ResponseShape
      private

      def shape_response(data)
        operation = @query.selected_operation
        parent_type = @query.root_type_for_operation(operation.operation_type)

        @path = []
        resolve_object_scope(data, parent_type, operation.selections)
      end

      def resolve_object_scope(raw_object, parent_type, selections)
        return nil if raw_object.nil?

        selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            field_name = node.alias || node.name
            @path << field_name

            begin
              node_type = @query.get_field(parent_type, node.name).type
              named_type = node_type.unwrap

              # delete and re-add to order result keys...
              raw_value = raw_object.delete(field_name)

              raw_object[field_name] = if raw_value.is_a?(ExecutionError)
                # capture errors encountered in the response with proper path
                @errors << if raw_value.is_a?(InvalidNullError) && raw_value.original_error
                  raw_value.original_error.path = @path.dup
                  raw_value.original_error
                else
                  raw_value.path = @path.dup
                  raw_value
                end
                nil
              elsif node_type.list?
                node_type = node_type.of_type while node_type.non_null?
                resolve_list_scope(raw_value, node_type, node.selections)
              elsif named_type.kind.leaf?
                raw_value
              else
                resolve_object_scope(raw_value, named_type, node.selections)
              end

              return nil if node_type.non_null? && raw_object[field_name].nil?
            ensure
              @path.pop
            end

          when GraphQL::Language::Nodes::InlineFragment
            fragment_type = node.type ? @query.get_type(node.type.name) : parent_type
            next unless typename_in_type?(raw_object.typename, fragment_type)

            result = resolve_object_scope(raw_object, fragment_type, node.selections)
            return nil if result.nil?

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @request.fragment_definitions[node.name]
            fragment_type = @query.get_type(fragment.type.name)
            next unless typename_in_type?(raw_object.typename, fragment_type)

            result = resolve_object_scope(raw_object, fragment_type, fragment.selections)
            return nil if result.nil?

          else
            raise DocumentError.new("selection node type")
          end
        end

        raw_object
      end

      def resolve_list_scope(raw_list, current_node_type, selections)
        return nil if raw_list.nil?

        current_node_type = current_node_type.of_type while current_node_type.non_null?
        next_node_type = current_node_type.of_type
        named_type = next_node_type.unwrap
        contains_null = false

        resolved_list = raw_list.map!.with_index do |raw_list_element, index|
          @path << index

          begin
            result = if next_node_type.list?
              resolve_list_scope(raw_list_element, next_node_type, selections)
            elsif named_type.kind.leaf?
              raw_list_element
            else
              resolve_object_scope(raw_list_element, named_type, selections)
            end

            if result.nil?
              contains_null = true
              return nil if current_node_type.non_null?
            end

            result
          ensure
            @path.pop
          end
        end

        return nil if contains_null && next_node_type.non_null?

        resolved_list
      end

      def typename_in_type?(typename, type)
        return true if type.graphql_name == typename

        type.kind.abstract? && @query.possible_types(type).any? do |t|
          t.graphql_name == typename
        end
      end
    end
  end
end
