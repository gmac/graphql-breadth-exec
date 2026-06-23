# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    class Executor
      # @requires_ancestor: Kernel
      module LazyElement
        LAZY_STATE_PRELOADING = :preloading
        LAZY_STATE_LOCKED = :locked

        def initialize(...)
          super(...)
          @sync_preloads = nil
          @lazy_preloads = nil
          @lazy_state = LAZY_STATE_PRELOADING
          @preload_promises = nil
        end

        #: () -> Array[ExecutionPromise]
        def preload_promises
          @preload_promises ||= []
        end

        #: () -> bool
        def lazy_preloads?
          @preload_promises && !@preload_promises.empty?
        end

        #: () -> bool
        def allows_preload?
          @lazy_state == LAZY_STATE_PRELOADING
        end

        #: () { (LazyElement) -> void } -> void
        def on_preload(&block)
          unless allows_preload?
            Kernel.raise LazySequencingError.new(lazy_element: self, method_name: "on_preload")
          end

          @sync_preloads ||= []
          @sync_preloads << block
        end

        #: (
        #|   singleton(GraphQL::Breadth::LazyLoader),
        #|   ?args: loader_args?,
        #|   ?keys: Array[untyped]?,
        #| ) -> ExecutionPromise
        def preload(loader_class, args: nil, keys: nil)
          unless allows_preload?
            Kernel.raise LazySequencingError.new(lazy_element: self, method_name: "preload")
          end

          if keys
            loader = executor.lazy_loader_for(loader_class, args)
            loader.load(element: self, keys: keys).with_registry(preload_promises)
          else
            @lazy_preloads ||= {}
            deferred = (@lazy_preloads[[loader_class, args]] ||= ExecutionPromise::Deferred.new(registry: preload_promises))
            deferred.promise
          end
        end

        #: () -> void
        def preload!
          while @sync_preloads && !@sync_preloads.empty?
            sync_preloads = @sync_preloads
            @sync_preloads = nil
            sync_preloads.each(&:call)
          end

          return unless @lazy_preloads

          preloads = @lazy_preloads
          @lazy_preloads = nil

          preloads.each do |(loader_class, args), pre_deferred|
            loader = executor.lazy_loader_for(loader_class, args)
            loader.load(element: self, keys: objects, pre_deferred: pre_deferred)
          end
        end

        #: (Array[ExecutionPromise]) -> ExecutionPromise
        def await_all(promises)
          promise = ExecutionPromise.all(promises)
          registry = promises.first&.registry

          if registry && promises.all? { _1.registry.equal?(registry) }
            promise.with_registry(registry)
          else
            promise
          end
        end

        #: () -> Array[untyped]
        def objects
          Kernel.raise NotImplementedError
        end

        #: () -> Executor
        def executor
          Kernel.raise NotImplementedError
        end

        #: () -> Array[String]
        def path
          Kernel.raise NotImplementedError
        end

        #: () -> void
        def lazy_state_locked!
          Kernel.raise LazyStateTransitionError.new(@lazy_state, LAZY_STATE_LOCKED) unless lazy_state_lockable?

          @lazy_state = LAZY_STATE_LOCKED
        end

        private

        #: () -> bool
        def lazy_state_lockable?
          @lazy_state == LAZY_STATE_PRELOADING
        end
      end
    end
  end
end
