# frozen_string_literal: true

module GraphQL::Cardinal
  class Executor
    module HotPaths
      INCORRECT_LIST_VALUE = "Incorrect result for list field. Expected Array, got ".freeze

      # DANGER: HOT PATH!
      # Overhead added here scales dramatically...
      def build_composite_response(exec_field, current_type, source, next_sources, next_responses)
        # if object authorization check implemented, then...
        # unless Authorization.can_access_object?(return_type, source, @context)

        if source.nil? || source.is_a?(ExecutionError)
          build_missing_value(exec_field, current_type, source)
        elsif current_type.list?
          unless source.is_a?(Array)
            report_exception("#{INCORRECT_LIST_VALUE}#{source.class}", field: exec_field)
            return build_missing_value(exec_field, current_type, nil)
          end

          current_type = current_type.of_type while current_type.non_null?

          source.map do |src|
            build_composite_response(exec_field, current_type.of_type, src, next_sources, next_responses)
          end
        else
          next_sources << source
          next_responses << ResponseHash.new
          next_responses.last
        end
      end

      # DANGER: HOT PATH!
      # Overhead added here scales dramatically...
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

      # DANGER: HOT PATH!
      # Overhead added here scales dramatically...
      def coerce_leaf_value(exec_field, current_type, val)
        if val.nil? || val.is_a?(StandardError)
          build_missing_value(exec_field, current_type, val)
        elsif current_type.list?
          unless val.is_a?(Array)
            report_exception("#{INCORRECT_LIST_VALUE}#{val.class}", field: exec_field)
            return build_missing_value(exec_field, current_type, nil)
          end

          current_type = current_type.of_type while current_type.non_null?

          val.map { coerce_leaf_value(exec_field, current_type.of_type, _1) }
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
    end
  end
end
