# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    #: [ContextType < GraphQL::Query::Context]
    class LazyLoader
      ConcurrencyConfig = Data.define(:enabled, :backend, :limit, :resource, :timeout)

      class LazyFulfillment
        #: Executor::LazyElement
        attr_reader :element

        #: Array[untyped]
        attr_reader :keys

        #: Array[untyped]
        attr_reader :identities

        #: Hash[untyped, untyped]?
        attr_reader :eager_values

        #: Executor::ExecutionPromise
        attr_reader :promise

        #: (
        #|   element: Executor::LazyElement,
        #|   keys: Array[untyped],
        #|   identities: Array[untyped],
        #|   ?eager_values: Hash[untyped, untyped]?,
        #|   ?pre_deferred: Executor::ExecutionPromise::Deferred?,
        #| ) -> void
        def initialize(element:, keys:, identities:, eager_values: nil, pre_deferred: nil)
          @element = element
          @keys = keys
          @identities = identities
          @eager_values = eager_values
          @resolver = pre_deferred&.resolver
          @promise = pre_deferred&.promise || Executor::ExecutionPromise.new { |resolve, _reject| @resolver = resolve }
        end

        #: (untyped) -> void
        def resolve(results)
          @resolver.call(results)
        end
      end

      KEY_OMISSION = Object.new.freeze
      DEFAULT_CONCURRENCY_CONFIG = ConcurrencyConfig.new(
        enabled: false,
        backend: :sync,
        limit: nil,
        resource: nil,
        timeout: nil,
      ).freeze

      class << self
        #: (?backend: Symbol, ?limit: Integer?, ?resource: untyped, ?timeout: Numeric?) -> void
        def concurrency(backend: :async, limit: 8, resource: nil, timeout: nil)
          raise ArgumentError, "Unsupported lazy concurrency backend: #{backend.inspect}" unless backend == :async
          raise ArgumentError, "Lazy concurrency limit must be positive" unless limit.nil? || limit.positive?
          raise ArgumentError, "Lazy concurrency timeout must be positive" unless timeout.nil? || (timeout.respond_to?(:positive?) && timeout.positive?)

          @concurrency_config = ConcurrencyConfig.new(
            enabled: true,
            backend: backend,
            limit: limit,
            resource: resource || self,
            timeout: timeout,
          ).freeze
        end

        #: -> ConcurrencyConfig
        def concurrency_config
          @concurrency_config || DEFAULT_CONCURRENCY_CONFIG
        end
      end

      #: Hash[untyped, untyped]
      attr_reader :pending_keys_by_identity

      #: Hash[untyped, untyped]
      attr_reader :results_by_identity

      #: Array[LazyFulfillment]
      attr_reader :promised

      #: -> void
      def initialize
        @pending_keys_by_identity = {}
        @results_by_identity = {}
        @promised = []
      end

      #: -> bool
      def map?
        false
      end

      #: -> bool
      def resolve_one?
        false
      end

      #: -> ConcurrencyConfig
      def concurrency_config
        self.class.concurrency_config
      end

      #: (Array[untyped], ContextType) -> void
      def perform(_keys, _context)
        raise NotImplementedError, "LazyLoader#perform must be implemented."
      end

      #: (Array[untyped], ContextType) -> Array[untyped]
      def perform_map(_keys, _context)
        raise NotImplementedError, "LazyLoader#perform_map must be implemented."
      end

      #: (untyped) -> untyped
      def identity_for(key)
        key
      end

      #: (untyped, untyped) -> void
      def fulfill_key(key, result)
        @results_by_identity[identity_for(key)] = result
      end

      #: (untyped, untyped) -> void
      def fulfill_identity(identity, result)
        @results_by_identity[identity] = result
      end

      #: (
      #|   element: Executor::LazyElement,
      #|   keys: Array[untyped],
      #|   ?eager_values: Hash[untyped, untyped]?,
      #|   ?load_nil_keys: bool,
      #|   ?pre_deferred: Executor::ExecutionPromise::Deferred?,
      #| ) -> Executor::ExecutionPromise
      def load(element:, keys:, eager_values: nil, load_nil_keys: false, pre_deferred: nil)
        eager_values = nil if eager_values&.empty?
        compact = !load_nil_keys
        pending = @pending_keys_by_identity
        results = @results_by_identity

        raise ImplementationError, "Provide exactly one key when resolving a single result" if resolve_one? && keys.size != 1

        identities = keys.map do |key|
          next KEY_OMISSION if (compact && key.nil?) || eager_values&.key?(key)

          identity = identity_for(key)
          pending[identity] ||= key unless results.key?(identity)
          identity
        end

        @promised << LazyFulfillment.new(
          element: element,
          keys: keys,
          identities: identities,
          eager_values: eager_values,
          pre_deferred: pre_deferred,
        )
        @promised.last.promise
      end

      #: (LazyFulfillment) -> untyped
      def collect_results(fulfillment)
        identities = fulfillment.identities
        results = @results_by_identity

        return results[identities.first] if resolve_one?

        if (eager_values = fulfillment.eager_values)
          keys = fulfillment.keys
          Array.new(identities.size) do |i|
            identity = identities[i]
            identity.equal?(KEY_OMISSION) ? eager_values[keys[i]] : results[identity]
          end
        else
          identities.map { results[_1] }
        end
      end

      #: (ContextType) -> void
      def execute!(context)
        fulfillments = @promised
        unless @pending_keys_by_identity.empty?
          pending_loader_keys = @pending_keys_by_identity.values

          if map?
            pending_loader_identities = @pending_keys_by_identity.keys
            reset!

            mapped_results = perform_map(pending_loader_keys, context)
            unless pending_loader_keys.size == mapped_results.size
              raise ImplementationError, "Wrong number of results. Expected #{pending_loader_keys.size}, got #{mapped_results.size}"
            end

            i = 0
            while i < pending_loader_identities.length
              @results_by_identity[pending_loader_identities[i]] = mapped_results[i]
              i += 1
            end
          else
            reset!
            perform(pending_loader_keys, context)
          end
        else
          reset!
        end

        fulfillments.each { |fulfillment| fulfillment.resolve(collect_results(fulfillment)) }
      end

      #: -> void
      def reset!
        @pending_keys_by_identity.clear
        @promised = []
      end
    end
  end
end
