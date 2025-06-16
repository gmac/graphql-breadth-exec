# frozen_string_literal: true

module GraphQL
  module Cardinal
    class SetLoader
      class << self
        def for(scope, key)
          scope[self][key] ||= new(key)
        end
      end

      def initialize
        @promised_sets = nil
        @mapping = nil
      end

      def perform(keys)
        raise NotImplementedError
      end

      def promised_sets
        @promised_sets ||= {}
      end

      def mapping
        @mapping ||= {}
      end

      def mapping_key(item)
        item
      end

      def load(items)
        items.each do |item|
          mapping[mapping_key(item)] = nil
        end

        ::Promise.new.tap { |p| p.source = self }
      end
    end
  end
end
