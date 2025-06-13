# typed: false
# frozen_string_literal: true

module GraphQL
  module Cardinal
    class Shaper
      class << self
        def perform(query, result)
          operation = query.selected_operation
          parent_type = query.root_type_for_operation(operation.operation_type)
          resolve_object_scope(query,  result, parent_type, operation.selections)
        end

        private

        def resolve_object_scope(query, raw_object, parent_type, selections, typename = nil)
          return nil if raw_object.nil?

          selections.each do |node|
            case node
            when GraphQL::Language::Nodes::Field
              field_name = node.alias || node.name
              node_type = query.get_field(parent_type, node.name).type
              named_type = node_type.unwrap
              raw_value = raw_object[field_name]

              raw_object[field_name] = if node_type.list?
                node_type = node_type.of_type while node_type.non_null?
                resolve_list_scope(query, raw_value, node_type, node.selections)
              elsif named_type.kind.leaf?
                raw_value
              else
                resolve_object_scope(query, raw_value, named_type, node.selections)
              end

              return nil if node_type.non_null? && raw_object[field_name].nil?

            when GraphQL::Language::Nodes::InlineFragment
              raise "Can't shape fragments yet"
              # fragment_type = node.type ? @supergraph.memoized_schema_types[node.type.name] : parent_type
              # next unless typename_in_type?(typename, fragment_type)

              # result = resolve_object_scope(query, raw_object, fragment_type, node.selections, typename)
              # return nil if result.nil?


            when GraphQL::Language::Nodes::FragmentSpread
              raise "Can't shape fragments yet"
              # fragment = @request.fragment_definitions[node.name]
              # fragment_type = @supergraph.memoized_schema_types[fragment.type.name]
              # next unless typename_in_type?(typename, fragment_type)

              # result = resolve_object_scope(query, raw_object, fragment_type, fragment.selections, typename)
              # return nil if result.nil?

            else
              raise DocumentError.new("selection node type")
            end
          end

          raw_object
        end

        def resolve_list_scope(query, raw_list, current_node_type, selections)
          return nil if raw_list.nil?

          current_node_type = current_node_type.of_type while current_node_type.non_null?
          next_node_type = current_node_type.of_type
          named_type = next_node_type.unwrap
          contains_null = false

          resolved_list = raw_list.map! do |raw_list_element|
            result = if next_node_type.list?
              resolve_list_scope(query, raw_list_element, next_node_type, selections)
            elsif named_type.kind.leaf?
              raw_list_element
            else
              resolve_object_scope(query, raw_list_element, named_type, selections)
            end

            if result.nil?
              contains_null = true
              return nil if current_node_type.non_null?
            end

            result
          end

          return nil if contains_null && next_node_type.non_null?

          resolved_list
        end
      end
    end
  end
end
