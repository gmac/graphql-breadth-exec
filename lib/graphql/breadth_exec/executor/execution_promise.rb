# typed: true
# frozen_string_literal: true

module GraphQL
  module BreadthExec
    class ExecutionPromise
      PENDING = :pending
      FULFILLED = :fulfilled
      REJECTED = :rejected

      #: Array[ExecutionPromise]?
      attr_reader :registry

      #: (?registry: Array[ExecutionPromise]?) ?{ (Proc, Proc) -> void } -> void
      def initialize(registry: nil, &executor)
        @state = PENDING
        @value = nil
        @reason = nil
        @observers = []
        @registry = nil
        with_registry(registry) if registry

        if executor
          begin
            executor.call(method(:resolve), method(:reject))
          rescue StandardError => e
            reject(e)
          end
        end
      end

      #: (Array[ExecutionPromise]) -> ExecutionPromise
      def self.all(promises)
        raise ArgumentError, "promises cannot be empty" if promises.empty?

        new do |resolve, reject|
          results = Array.new(promises.length)
          completed = 0
          promises.each_with_index do |promise, index|
            promise.then(
              ->(value) {
                results[index] = value
                completed += 1
                resolve.call(results) if completed == promises.length
              },
              reject,
            )
          end
        end
      end

      #: (Array[ExecutionPromise]) -> ExecutionPromise
      def with_registry(registry)
        @registry = registry
        registry << self unless registry.include?(self)
        self
      end

      #: (
      #|   ?(^(untyped value) -> untyped | Proc)? on_fulfilled,
      #|   ?(^(untyped) -> void | Proc)? on_rejected
      #| ) ?{ (untyped) -> untyped } -> ExecutionPromise
      def then(on_fulfilled = nil, on_rejected = nil, &block)
        raise ArgumentError, "Either on_fulfilled or block is required" unless on_fulfilled || on_rejected || block_given?
        raise ArgumentError, "Exactly one of on_fulfilled or block is required" if on_fulfilled && block_given?

        next_promise = self.class.new(registry: @registry)
        fulfilled_handler = on_fulfilled || block
        rejected_handler = on_rejected || ->(reason) { raise reason }

        if resolved?
          next_promise.send(:dispatch_fulfilled, @value, fulfilled_handler)
        elsif rejected?
          next_promise.send(:dispatch_rejected, @reason, rejected_handler)
        else
          @observers << [next_promise, fulfilled_handler, rejected_handler]
        end

        next_promise
      end

      #: (?(^(untyped) -> void | Proc)? on_rejected) ?{ (untyped) -> untyped } -> ExecutionPromise
      def catch(on_rejected = nil, &block)
        self.then(->(value) { value }, on_rejected || block)
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

      private

      #: (untyped) -> void
      def resolve(value)
        return unless pending?

        if value.is_a?(ExecutionPromise)
          if value.equal?(self)
            reject(StandardError.new("A promise cannot resolve to itself"))
          elsif value.resolved?
            resolve(value.value)
          elsif value.rejected?
            reject(value.reason)
          else
            value.then(method(:resolve), method(:reject))
          end
          return
        end

        @state = FULFILLED
        @value = value
        notify_fulfilled
      end

      #: (untyped) -> void
      def reject(reason)
        return unless pending?

        @state = REJECTED
        @reason = reason
        notify_rejected
      end

      #: (untyped, Proc?) -> void
      def dispatch_fulfilled(value, handler)
        handler ? settle_from_handler(value, handler) : resolve(value)
      end

      #: (untyped, Proc?) -> void
      def dispatch_rejected(reason, handler)
        handler ? settle_from_handler(reason, handler) : reject(reason)
      end

      #: (untyped, Proc) -> void
      def settle_from_handler(input, handler)
        resolve(handler.call(input))
      rescue StandardError => e
        reject(e)
      end

      #: () -> void
      def notify_fulfilled
        observers = @observers
        @observers = []
        observers.each do |promise, on_fulfilled, _on_rejected|
          promise.send(:dispatch_fulfilled, @value, on_fulfilled)
        end
      end

      #: () -> void
      def notify_rejected
        observers = @observers
        @observers = []
        observers.each do |promise, _on_fulfilled, on_rejected|
          promise.send(:dispatch_rejected, @reason, on_rejected)
        end
      end
    end

    class Deferred
      #: ExecutionPromise
      attr_reader :promise

      #: ^(untyped) -> untyped
      attr_reader :resolver

      #: (?registry: Array[ExecutionPromise]?) -> void
      def initialize(registry: nil)
        @resolver = nil
        @promise = ExecutionPromise.new(registry: registry) do |resolve, _reject|
          @resolver = resolve
        end
      end
    end
  end
end
