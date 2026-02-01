# frozen_string_literal: true

module GraphQL::BreadthExec
  class Executor
    class ExecutionScope
      attr_reader :parent_type, :selections, :objects, :results, :path, :parent
      attr_accessor :fields

      def initialize(
        parent_type:,
        selections:,
        objects:,
        results:,
        loader_cache: nil,
        loader_group: nil,
        path: [],
        parent: nil
      )
        @parent_type = parent_type
        @selections = selections
        @objects = objects
        @results = results
        @loader_cache = loader_cache
        @loader_group = loader_group
        @path = path.freeze
        @parent = parent
        @fields = nil
      end

      def defer(loader_class, keys:, group: nil)
        loader = loader_cache[[loader_class, group]] ||= loader_class.new(group)
        loader.load(keys)
      end

      def lazy_fields?
        @fields&.each_value&.any? { _1.result.is_a?(Promise) } || false
      end

      # is this scope ungrouped, or have all scopes in the group built their fields?
      def lazy_fields_ready?
        !@loader_group || @loader_group.all?(&:fields)
      end

      private

      def loader_cache
        @loader_cache ||= {}
      end

      def lazy_exec!
        loader_cache.each_value { |loader| loader.send(:lazy_exec!) }
      end
    end
  end
end
