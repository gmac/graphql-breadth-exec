# frozen_string_literal: true

module GraphQL::Cardinal
  class Executor
    module HotPaths
      # DANGER: HOT PATHS!
      # Overhead added here scales dramatically...

      INCORRECT_LIST_VALUE = "Incorrect result for list field. Expected Array, got ".freeze

      def build_composite_result(exec_field, current_type, object, next_objects, next_results)
        if object.nil? || object.is_a?(ExecutionError)
          build_missing_value(exec_field, current_type, object)
        elsif current_type.list?
          unless object.is_a?(Array)
            report_exception("#{INCORRECT_LIST_VALUE}#{object.class}", field: exec_field)
            return build_missing_value(exec_field, current_type, nil)
          end

          current_type = current_type.of_type while current_type.non_null?

          object.map do |src|
            build_composite_result(exec_field, current_type.of_type, src, next_objects, next_results)
          end
        else
          next_objects << object
          next_results << ResultHash.new
          next_results.last
        end
      end

      def build_leaf_result(exec_field, current_type, val)
        if val.nil? || val.is_a?(StandardError)
          build_missing_value(exec_field, current_type, val)
        elsif current_type.list?
          unless val.is_a?(Array)
            report_exception("#{INCORRECT_LIST_VALUE}#{val.class}", field: exec_field)
            return build_missing_value(exec_field, current_type, nil)
          end

          current_type = current_type.of_type while current_type.non_null?

          val.map { build_leaf_result(exec_field, current_type.of_type, _1) }
        else
          begin
            current_type.unwrap.coerce_result(val, @context)
          rescue StandardError => e
            report_exception("Error building leaf result", error: e, field: exec_field)
            error = InternalError.new(path: exec_field.path, base: false)
            build_missing_value(exec_field, current_type, error)
          end
        end
      end

      def build_missing_value(exec_field, current_type, val)
        # the provided value should always be nil or an error object
        if current_type.non_null?
          val ||= InvalidNullError.new(path: exec_field.path)
        end

        if val
          val.replace_path(exec_field.path) unless val.path
          @errors << val unless val.base_error?
        end

        val
      end
    end
  end
end
