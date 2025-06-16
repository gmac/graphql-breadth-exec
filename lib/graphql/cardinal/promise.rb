# frozen_string_literal: true

module GraphQL
  module Cardinal
    class Promise
      PENDING = :pending
      FULFILLED = :fulfilled
      REJECTED = :rejected

      def initialize
        @state = PENDING
        @value = nil
        @reason = nil
        @on_fulfilled = []
        @on_rejected = []

        if block_given?
          begin
            yield(method(:resolve), method(:reject))
          rescue => error
            reject(error)
          end
        end
      end

      def self.all(promises)
        return Promise.resolve([]) if promises.empty?

        Promise.new do |resolve, reject|
          results = Array.new(promises.length)
          completed = 0

          promises.each_with_index do |promise, index|
            promise.then(
              ->(value) {
                results[index] = value
                completed += 1
                resolve.call(results) if completed == promises.length
              },
              ->(reason) { reject.call(reason) }
            )
          end
        end
      end

      def then(on_fulfilled = nil, on_rejected = nil)
        Promise.new do |resolve, reject|
          handle_then(
            on_fulfilled || ->(value) { value },
            on_rejected || ->(reason) { raise reason },
            resolve,
            reject
          )
        end
      end

      def catch(on_rejected = nil)
        self.then(nil, on_rejected)
      end

      def resolved?
        @state == FULFILLED
      end

      def rejected?
        @state == REJECTED
      end

      def pending?
        @state == PENDING
      end

      def value
        @value if resolved?
      end

      def reason
        @reason if rejected?
      end

      def resolve(value)
        return unless pending?

        @state = FULFILLED
        @value = value
        @on_fulfilled.each { |callback| callback.call(value) }
        @on_fulfilled.clear
        @on_rejected.clear
      end

      def reject(reason)
        return unless pending?

        @state = REJECTED
        @reason = reason
        @on_rejected.each { |callback| callback.call(reason) }
        @on_fulfilled.clear
        @on_rejected.clear
      end

      private

      def handle_then(on_fulfilled, on_rejected, resolve, reject)
        if resolved?
          begin
            result = on_fulfilled.call(@value)
            resolve.call(result)
          rescue => error
            reject.call(error)
          end
        elsif rejected?
          begin
            result = on_rejected.call(@reason)
            result.is_a?(Promise) ? result.then(resolve, reject) : resolve.call(result)
          rescue => error
            reject.call(error)
          end
        else
          @on_fulfilled << ->(value) {
            begin
              result = on_fulfilled.call(value)
              result.is_a?(Promise) ? result.then(resolve, reject) : resolve.call(result)
            rescue => error
              reject.call(error)
            end
          }
          @on_rejected << ->(reason) {
            begin
              result = on_rejected.call(reason)
              result.is_a?(Promise) ? result.then(resolve, reject) : resolve.call(result)
            rescue => error
              reject.call(error)
            end
          }
        end
      end
    end
  end
end
