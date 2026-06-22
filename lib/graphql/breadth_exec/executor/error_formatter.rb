# typed: true
# frozen_string_literal: true

module GraphQL::BreadthExec
  class Executor
    class ErrorFormatter
      class State
        #: Array[Hash[String, untyped]]
        attr_reader :errors

        #: error_path
        attr_reader :actual_path

        #: error_path
        attr_reader :base_path

        #: (?error_path) -> void
        def initialize(base_path = EMPTY_ARRAY)
          @base_path = base_path
          @actual_path = []
          @errors = []
        end

        #: -> error_path
        def current_path
          @base_path + @actual_path
        end
      end

      #: (
      #|   executor: Executor,
      #|   invalidated_results: Hash[untyped, ExecutionError],
      #|   abstract_result_types: Hash[untyped, singleton(GraphQL::Schema::Object)],
      #| ) -> void
      def initialize(executor:, invalidated_results:, abstract_result_types:)
        @executor = executor
        @context = executor.context
        @invalidated_results = invalidated_results
        @abstract_result_types = abstract_result_types
      end

      #: (
      #|   singleton(GraphQL::Schema::Object),
      #|   Array[selection_node],
      #|   Hash[String, untyped],
      #|   ?error_path,
      #| ) -> [Hash[String, untyped]?, Array[error_hash]]
      def format_object(parent_type, selections, data, base_path = EMPTY_ARRAY)
        return [data, EMPTY_ARRAY] if @invalidated_results.empty?

        state = State.new(base_path)

        if (err = @invalidated_results[data])
          add_formatted_error(err, state)
          return [nil, state.errors]
        end

        data = propagate_object_scope_errors(data, parent_type, selections, state)
        [data, state.errors]
      end

      private

      #: (untyped, singleton(GraphQL::Schema::Object), Array[selection_node], State) -> untyped
      def propagate_object_scope_errors(raw_object, parent_type, selections, state)
        return nil if raw_object.nil?

        selections.each do |node|
          case node
          when GraphQL::Language::Nodes::Field
            field_key = node.alias || node.name

            state.actual_path << field_key

            begin
              node_type = @context.types.field(parent_type, node.name).type
              named_type = node_type.unwrap
              raw_value = raw_object.fetch(field_key, Executor::UNDEFINED)
              next if raw_value.equal?(Executor::UNDEFINED)

              raw_object[field_key] = if (err = @invalidated_results[raw_value])
                add_formatted_error(err, state)
                nil
              elsif node_type.list?
                propagate_list_scope_errors(raw_value, node_type, node.selections, state)
              elsif named_type.kind.leaf?
                raw_value
              else
                propagate_object_scope_errors(raw_value, named_type, node.selections, state)
              end

              return nil if node_type.non_null? && raw_object[field_key].nil?
            ensure
              state.actual_path.pop
            end

          when GraphQL::Language::Nodes::InlineFragment
            fragment_type = node.type ? @context.types.type(node.type.name) : parent_type
            next unless result_of_type?(raw_object, parent_type, fragment_type)

            result = propagate_object_scope_errors(raw_object, fragment_type, node.selections, state)
            return nil if result.nil?

          when GraphQL::Language::Nodes::FragmentSpread
            fragment = @executor.fragments.fetch(node.name)
            fragment_type = @context.types.type(fragment.type.name)
            next unless result_of_type?(raw_object, parent_type, fragment_type)

            result = propagate_object_scope_errors(raw_object, fragment_type, fragment.selections, state)
            return nil if result.nil?
          end
        end

        raw_object
      end

      #: (Array[untyped]?, singleton(GraphQL::Schema::Member), Array[selection_node], State) -> Array[untyped]?
      def propagate_list_scope_errors(raw_list, current_node_type, selections, state)
        return nil if raw_list.nil?

        item_node_type = Util.unwrap_non_null(current_node_type).of_type
        named_type = item_node_type.unwrap

        raw_list.map!.with_index do |raw_list_element, index|
          state.actual_path << index

          begin
            result = if (err = @invalidated_results[raw_list_element])
              add_formatted_error(err, state)
              nil
            elsif item_node_type.list?
              propagate_list_scope_errors(raw_list_element, item_node_type, selections, state)
            elsif named_type.kind.leaf?
              raw_list_element
            else
              propagate_object_scope_errors(raw_list_element, named_type, selections, state)
            end

            return nil if result.nil? && item_node_type.non_null?

            result
          ensure
            state.actual_path.pop
          end
        end
      end

      #: (untyped, singleton(GraphQL::Schema::Member), singleton(GraphQL::Schema::Member)) -> bool
      def result_of_type?(result, current_type, inquiry_type)
        result_type = current_type.kind.abstract? ? @abstract_result_types[result] : current_type
        raise ImplementationError, "No type annotation recorded for abstract result" if result_type.nil?

        if inquiry_type.kind.abstract?
          @context.types.possible_types(inquiry_type).include?(result_type)
        else
          result_type == inquiry_type
        end
      end

      #: (ExecutionError, State) -> void
      def add_formatted_error(error, state)
        error.each do |err|
          next if err.equal?(UNREPORTED_ERROR)

          state.errors << err.to_h.tap { _1["path"] = state.current_path }
          @context.errors << err.cause if err.cause
        end
      end
    end
  end
end
