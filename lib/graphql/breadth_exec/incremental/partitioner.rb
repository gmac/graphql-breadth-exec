# typed: true
# frozen_string_literal: true

module GraphQL
  module BreadthExec
    module Incremental
      class Partitioner
        class << self
          #: (
          #|   Hash[String, Array[Incremental::Selection]] field_selections,
          #|   parent_usages: Set[DeferUsage],
          #| ) -> [Hash[String, Array[Incremental::Selection]], Hash[Set[DeferUsage], Hash[String, Array[Incremental::Selection]]]]
          def partition(field_selections, parent_usages:)
            base_field_selections = {}
            field_selections_by_defer_usage = {}

            field_selections.each do |response_key, incremental_selections|
              filtered_defer_usage_set = defer_usages_for(incremental_selections)

              if same_set?(filtered_defer_usage_set, parent_usages)
                base_field_selections[response_key] = incremental_selections
                next
              end

              deferred_field_selections = field_selections_for_defer_usage(field_selections_by_defer_usage, filtered_defer_usage_set)
              deferred_field_selections[response_key] = incremental_selections
            end

            [base_field_selections, field_selections_by_defer_usage]
          end

          #: (Array[Incremental::Selection]) -> Set[DeferUsage]
          def defer_usages_for(incremental_selections)
            filtered = Set.new.compare_by_identity

            incremental_selections.each do |incremental_selection|
              defer_usage = incremental_selection.defer_usage
              return EMPTY_SET unless defer_usage

              filtered << defer_usage
            end

            filtered.each do |defer_usage|
              parent = defer_usage.parent
              while parent
                if filtered.include?(parent)
                  filtered.delete(defer_usage)
                  break
                end

                parent = parent.parent
              end
            end

            filtered.freeze
          end

          private

          #: (
          #|   Hash[Set[DeferUsage], Hash[String, Array[Incremental::Selection]]],
          #|   Set[DeferUsage],
          #| ) -> Hash[String, Array[Incremental::Selection]]
          def field_selections_for_defer_usage(field_selections_by_defer_usage, defer_usage_set)
            existing = field_selections_by_defer_usage.find { |set, _| same_set?(set, defer_usage_set) }
            return existing[1] if existing

            field_selections = {}
            field_selections_by_defer_usage[defer_usage_set] = field_selections
            field_selections
          end

          #: (Set[DeferUsage], Set[DeferUsage]) -> bool
          def same_set?(left, right)
            return true if left.equal?(right)
            return false unless left.size == right.size

            left.all? { right.include?(_1) }
          end
        end
      end
    end
  end
end
