# frozen_string_literal: true

module GraphQL::Cardinal
  class BreadthExecutor
    class Tracer
      def initialize
        @time = nil
      end

      def before_resolve_field(parent_type, field_name, sources_count, context)
        @time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def after_resolve_field(parent_type, field_name, sources_count, context)
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @time) / sources_count
      end
    end
  end
end
