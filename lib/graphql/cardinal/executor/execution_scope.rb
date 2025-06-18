# frozen_string_literal: true

module GraphQL::Cardinal
  class Executor
    class ExecutionScope
      attr_reader :parent_type, :selections, :sources, :responses, :parent
      attr_accessor :fields

      def initialize(
        parent_type:,
        selections:,
        sources:,
        responses:,
        loader_cache: nil,
        loader_group: nil,
        parent: nil
      )
        @parent_type = parent_type
        @selections = selections
        @sources = sources
        @responses = responses
        @loader_cache = loader_cache
        @loader_group = loader_group
        @parent = parent
        @fields = nil
      end

      def defer(loader_class, keys:, group: nil)
        loader = loader_cache[[loader_class, group]] ||= loader_class.new(group)
        loader.load(keys)
      end

      # does any field in this scope have a pending promise?
      def lazy_fields_pending?
        @fields&.each_value&.any? { _1.promise&.pending? } || false
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
        loader_cache.each_value { |loader| loader.method(:lazy_exec!).call }
      end
    end
  end
end
