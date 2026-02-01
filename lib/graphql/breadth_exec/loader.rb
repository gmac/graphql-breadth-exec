# frozen_string_literal: true

module GraphQL
  module BreadthExec
    class Loader
      attr_reader :group

      def initialize(group)
        @group = group
        @map = {}
        @promised = {}
        @performed = false
      end

      def perform(keys)
        raise NotImplementedError
      end

      def map_key(key)
        key
      end

      def load(keys)
        keys.each do |key|
          @map[map_key(key)] ||= key
        end

        promised = @promised
        Promise.new do |resolve, reject|
          promised[resolve] = keys
        end
      end

      private

      def lazy_exec!
        return if @performed

        @performed = true
        all_keys = @map.values.freeze
        all_results = perform(all_keys)
        unless all_keys.size == all_results.size
          raise "Wrong number of results. Expected #{all_keys.size}, got #{all_results.size}"
        end

        all_keys.each_with_index do |key, index|
          @map[map_key(key)] = all_results[index]
        end

        @promised.each do |resolve, keys|
          resolve.call(keys.map { |key| @map[map_key(key)] })
        end

        nil
      end
    end
  end
end
