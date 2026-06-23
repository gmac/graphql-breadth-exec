# typed: true
# frozen_string_literal: true

module GraphQL
  module BreadthExec
    module Incremental
      class DeferredExecutionScope < Executor::ExecutionScope
        #: Executor::ExecutionScope
        attr_reader :base_scope

        #: Hash[String, Array[Incremental::Selection]]
        attr_reader :field_selections

        #: Set[DeferUsage]
        attr_reader :defer_usages

        #: bool
        attr_writer :announced

        #: (
        #|   base_scope: Executor::ExecutionScope,
        #|   field_selections: Hash[String, Array[Incremental::Selection]],
        #|   defer_usages: Set[DeferUsage],
        #| ) -> void
        def initialize(base_scope:, field_selections:, defer_usages:)
          @base_scope = base_scope
          @field_selections = field_selections
          @defer_usages = defer_usages
          @announced = false

          super(
            executor: base_scope.executor,
            parent_type: base_scope.parent_type,
            selections: field_selections.each_value.flat_map { |incremental_selections| incremental_selections.map(&:node) }.freeze,
            objects: EMPTY_ARRAY,
            results: EMPTY_ARRAY,
            abstraction: base_scope.abstraction,
            parent_field: base_scope.parent_field,
            path: base_scope.path,
            parent: base_scope.parent,
            deferred: true,
          )
        end

        #: -> bool
        def ready?
          @base_scope.has_authorized_objects? && @base_scope.executed? && !@base_scope.aborted?
        end

        #: -> bool
        def announced?
          @announced
        end

        #: -> DeferredExecutionScope
        def prepare!
          if @results.empty?
            @objects = @base_scope.objects
            @results = Array.new(@base_scope.objects.size) { {} }.freeze
          end

          self
        end
      end
    end
  end
end
