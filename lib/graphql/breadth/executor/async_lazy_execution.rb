# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    class Executor
      # @requires_ancestor: Executor
      module AsyncLazyExecution
        class State
          #: Async::Barrier
          attr_reader :barrier

          #: Async::Queue
          attr_reader :completed_jobs

          #: Hash[LazyLoader[untyped], bool]
          attr_reader :active_loaders

          #: Integer
          attr_accessor :active_count

          #: Array[LazyElement]
          attr_accessor :waiting_elements

          #: Hash[LazyElement, bool]
          attr_reader :waiting_elements_by_identity

          #: Hash[untyped, Async::Semaphore]
          attr_reader :semaphores_by_resource

          #: (Async::Task) -> void
          def initialize(task)
            @barrier = Async::Barrier.new(parent: task)
            @completed_jobs = Async::Queue.new
            @active_loaders = {}.compare_by_identity
            @active_count = 0
            @waiting_elements = []
            @waiting_elements_by_identity = {}.compare_by_identity
            @semaphores_by_resource = {}
          end
        end

        private

        #: (Array[LazyJob], Array[LazyJob], Hash[ExecutionScope, bool]) -> void
        def execute_async_lazy_jobs(sync_jobs, async_jobs, aborted_status_cache)
          unless GraphQL::Breadth.async_enabled?
            Kernel.raise ImplementationError, "Async lazy loaders require `GraphQL::Breadth.enable_async!` during application boot."
          end

          Kernel.Sync do |task|
            state = State.new(task)

            begin
              async_jobs.each { schedule_async_lazy_job(state, _1) }
              sync_jobs.each { execute_sync_lazy_job(state, _1, aborted_status_cache) }

              until state.active_count.zero?
                finish_async_lazy_job(state, aborted_status_cache)
              end

              retry_waiting_lazy_elements(state, aborted_status_cache)
            ensure
              state.barrier.stop if state.active_count.positive?
            end
          end
        end

        #: (State, LazyJob) -> void
        def schedule_async_lazy_job(state, job)
          settings = job.loader.concurrency_settings
          limit = settings.limit
          parent = if limit
            state.semaphores_by_resource[settings.resource] ||= Async::Semaphore.new(limit, parent: state.barrier)
          else
            state.barrier
          end

          state.active_loaders[job.loader] = true
          state.active_count += 1

          parent.async do |async_task|
            error = begin
              if settings.timeout
                async_task.with_timeout(settings.timeout) { execute_lazy_job(job, apply_errors: false) }
              else
                execute_lazy_job(job, apply_errors: false)
              end
            rescue Exception => e
              e
            end

            state.completed_jobs << job.with(error: error)
          end
        end

        #: (State, LazyJob, Hash[ExecutionScope, bool]) -> void
        def execute_sync_lazy_job(state, job, aborted_status_cache)
          error = execute_lazy_job(job, apply_errors: false)
          apply_lazy_loader_error(job, error) if error

          requeued_elements = resume_lazy_elements(job.elements, aborted_status_cache, capture_requeued: true)
          drain_requeued_lazy_elements(state, requeued_elements, aborted_status_cache)
        end

        #: (State, Hash[ExecutionScope, bool]) -> void
        def finish_async_lazy_job(state, aborted_status_cache)
          job = state.completed_jobs.dequeue
          state.active_count -= 1
          state.active_loaders.delete(job.loader)

          if job.error
            Kernel.raise job.error unless job.error.is_a?(StandardError)

            apply_lazy_loader_error(job, job.error)
          end

          requeued_elements = resume_lazy_elements(job.elements, aborted_status_cache, capture_requeued: true)
          drain_requeued_lazy_elements(state, requeued_elements, aborted_status_cache)
          retry_waiting_lazy_elements(state, aborted_status_cache)
        end

        #: (State, Hash[ExecutionScope, bool]) -> Hash[LazyElement, bool]
        def schedule_pending_lazy_jobs(state, aborted_status_cache)
          pending_jobs = []
          (@loader_cache || EMPTY_OBJECT).each_value do |loader|
            next if loader.promised.empty? || state.active_loaders.key?(loader)

            loader_elements = loader.promised.map(&:element)
            all_aborted = loader_elements.all? do |element|
              aborted_status_cache[element.is_a?(ExecutionField) ? element.scope : element]
            end

            if all_aborted
              loader.reset!
            else
              pending_jobs << LazyJob.new(loader: loader, elements: loader_elements, error: nil)
            end
          end

          return EMPTY_OBJECT if pending_jobs.empty?

          scheduled_elements = {}.compare_by_identity
          sync_pending_jobs, async_pending_jobs = partition_lazy_jobs(pending_jobs)
          pending_jobs.each { |job| job.elements.each { scheduled_elements[_1] = true } }

          async_pending_jobs&.each { schedule_async_lazy_job(state, _1) }
          sync_pending_jobs&.each { execute_sync_lazy_job(state, _1, aborted_status_cache) }

          scheduled_elements
        end

        #: (State, Array[LazyElement], Hash[ExecutionScope, bool]) -> void
        def drain_requeued_lazy_elements(state, elements, aborted_status_cache)
          return if elements.empty?

          scheduled_elements = schedule_pending_lazy_jobs(state, aborted_status_cache)
          if scheduled_elements.empty?
            enqueue_waiting_lazy_elements(state, elements)
          else
            elements.each do |element|
              enqueue_waiting_lazy_elements(state, [element]) unless scheduled_elements.key?(element)
            end
          end
        end

        #: (State, Array[LazyElement]) -> void
        def enqueue_waiting_lazy_elements(state, elements)
          elements.each do |element|
            next if state.waiting_elements_by_identity.key?(element)

            state.waiting_elements_by_identity[element] = true
            state.waiting_elements << element
          end
        end

        #: (State, Hash[ExecutionScope, bool]) -> void
        def retry_waiting_lazy_elements(state, aborted_status_cache)
          return if state.waiting_elements.empty?

          elements = state.waiting_elements
          state.waiting_elements = []
          state.waiting_elements_by_identity.clear

          requeued_elements = resume_lazy_elements(elements, aborted_status_cache, capture_requeued: true)
          drain_requeued_lazy_elements(state, requeued_elements, aborted_status_cache)
        end
      end
    end
  end
end
