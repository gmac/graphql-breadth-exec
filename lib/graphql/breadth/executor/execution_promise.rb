# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    class Executor
      class ExecutionPromise
        class Deferred
          #: Executor::ExecutionPromise
          attr_reader :promise

          #: ^(untyped) -> untyped
          attr_reader :resolver

          #: (?registry: Array[ExecutionPromise]?) -> void
          def initialize(registry: nil)
            @resolver = nil
            @promise = ExecutionPromise.new(registry:) { |resolve, _| @resolver = resolve }
          end
        end

        PENDING = :pending
        FULFILLED = :fulfilled
        REJECTED = :rejected

        RAISE_REASON = ->(reason) { raise reason }
        IDENTITY = ->(value) { value }

        class << self
          #: (Array[ExecutionPromise]) -> ExecutionPromise
          def all(promises)
            raise ArgumentError, "promises cannot be empty" if promises.empty?

            ExecutionPromise.new do |resolve, reject|
              results = Array.new(promises.length)
              completed = 0
              total = promises.length

              promises.each_with_index do |promise, index|
                promise.then(
                  ->(value) {
                    results[index] = value
                    completed += 1
                    resolve.call(results) if completed == total
                  },
                  reject,
                )
              end
            end
          end
        end

        attr_reader :registry

        #: (?registry: Array[ExecutionPromise]?) ?{ (Proc, Proc) -> void } -> void
        def initialize(registry: nil, &block)
          @state = PENDING
          @value = nil #: untyped
          @reason = nil #: Exception?
          @observers = nil #: Array[untyped]?

          with_registry(registry) if registry

          if block_given?
            begin
              yield(
                ->(value) { resolve(value) },
                ->(reason) { reject(reason) }
              )
            rescue => init_error
              reject(init_error)
            end
          end
        end

        #: (Array[ExecutionPromise]) -> ExecutionPromise
        def with_registry(registry)
          @registry = registry
          @registry << self unless registry.include?(self)
          self
        end

        #: (
        #|   ?(^(untyped value) -> untyped | Proc)? on_fulfilled,
        #|   ?(^(Exception) -> void | Proc)? on_rejected
        #| ) ?{ (untyped) -> untyped } -> ExecutionPromise
        def then(on_fulfilled = nil, on_rejected = nil, &block)
          raise ArgumentError, "Either on_fulfilled or block is required" unless on_fulfilled || block_given?
          raise ArgumentError, "Exactly one of on_fulfilled or block is required" if on_fulfilled && block_given?

          handler = on_fulfilled || block
          next_promise = ExecutionPromise.new(registry: @registry)

          case @state
          when FULFILLED
            next_promise.dispatch_fulfilled(@value, handler)
          when REJECTED
            next_promise.dispatch_rejected(@reason, on_rejected || RAISE_REASON)
          else
            subscribe(next_promise, handler, on_rejected || RAISE_REASON)
          end

          next_promise
        end

        def catch(on_rejected = nil, &block)
          self.then(IDENTITY, on_rejected || block)
        end

        #: () -> bool
        def resolved?
          @state == FULFILLED
        end

        #: () -> bool
        def rejected?
          @state == REJECTED
        end

        #: () -> bool
        def pending?
          @state == PENDING
        end

        #: () -> untyped?
        def value
          @value if resolved?
        end

        #: () -> untyped?
        def reason
          @reason if rejected?
        end

        protected

        #: (untyped, Proc?) -> void
        def dispatch_fulfilled(value, handler)
          if handler
            settle_from_handler(value, handler)
          else
            resolve(value)
          end
        end

        #: (untyped, Proc?) -> void
        def dispatch_rejected(reason, handler)
          if handler
            settle_from_handler(reason, handler)
          else
            reject(reason)
          end
        end

        #: (ExecutionPromise, Proc?, Proc?) -> void
        def subscribe(observer, on_fulfilled, on_rejected)
          if @observers
            @observers.push(observer, on_fulfilled, on_rejected)
          else
            @observers = [observer, on_fulfilled, on_rejected]
          end
        end

        private

        #: (untyped) -> void
        def resolve(result)
          return unless @state == PENDING

          if result.is_a?(ExecutionPromise)
            if result.equal?(self)
              reject(ArgumentError.new("A promise cannot resolve to itself"))
              return
            end

            if result.resolved?
              resolve(result.value)
            elsif result.rejected?
              reject(result.reason)
            else
              result.subscribe(self, nil, nil)
            end
          else
            @state = FULFILLED
            @value = result
            notify_fulfilled
          end
        end

        #: (untyped) -> void
        def reject(reason)
          return unless @state == PENDING

          @state = REJECTED
          @reason = reason
          notify_rejected
        end

        #: (untyped, Proc) -> void
        def settle_from_handler(input, handler)
          resolve(handler.call(input))
        rescue => error
          reject(error)
        end

        #: () -> void
        def notify_fulfilled
          return unless @observers

          observers = @observers
          @observers = nil
          i = 0
          while i < observers.length
            observers[i].dispatch_fulfilled(@value, observers[i + 1])
            i += 3
          end
        end

        #: () -> void
        def notify_rejected
          return unless @observers

          observers = @observers
          @observers = nil
          i = 0
          while i < observers.length
            observers[i].dispatch_rejected(@reason, observers[i + 2])
            i += 3
          end
        end
      end
    end
  end
end
