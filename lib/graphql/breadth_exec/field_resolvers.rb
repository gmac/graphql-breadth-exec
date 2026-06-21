# typed: true
# frozen_string_literal: true

module GraphQL
  module BreadthExec
    #: [ContextType < GraphQL::Query::Context]
    class FieldResolver
      #: (Executor::ExecutionField[untyped], ContextType) -> void
      def plan(_exec_field, _ctx)
        nil
      end

      #: (Executor::ExecutionField[untyped], ContextType) -> (Array[untyped] | ExecutionPromise)
      def resolve(*)
        raise NotImplementedError, "Resolver#resolve must be implemented."
      end

      #: (Executor::ExecutionField[untyped], ContextType) -> (Array[untyped] | ExecutionPromise)
      def resolve_field(exec_field, ctx)
        resolve(exec_field, ctx)
      end

      #: (Executor::ExecutionField[untyped], ContextType) -> untyped
      def subscribe(exec_field, ctx)
        resolve_field(exec_field, ctx)
      end

      #: (Array[untyped] | ExecutionPromise) { (Array[untyped]) -> Array[untyped] } -> (Array[untyped] | ExecutionPromise)
      def handle_resolved(result)
        if result.is_a?(ExecutionPromise)
          result.then { |values| yield(values) }
        else
          yield(result)
        end
      end
    end

    #: [ContextType = GraphQL::Query::Context]
    class HashKeyResolver < FieldResolver
      #: String | Symbol
      attr_reader :key

      #: (String | Symbol) -> void
      def initialize(key)
        @key = key
      end

      #: (Executor::ExecutionField[untyped], ContextType) -> Array[untyped]
      def resolve(exec_field, _ctx)
        exec_field.map_objects { _1[@key] }
      end
    end

    #: [ContextType = GraphQL::Query::Context]
    class MethodResolver < FieldResolver
      #: type method_name = String | Symbol

      #: (method_name, *method_name, ?fallback: untyped) -> void
      def initialize(*names, fallback: nil)
        @names = names
        @fallback = fallback
      end

      #: (Executor::ExecutionField[untyped], ContextType) -> Array[untyped]
      def resolve(exec_field, _ctx)
        exec_field.map_objects do |obj|
          @names.reduce(obj) do |memo, name|
            break @fallback if memo.nil? && !@fallback.nil?
            break memo if memo.nil?

            memo.public_send(name)
          end
        end
      end
    end

    #: [ContextType = GraphQL::Query::Context]
    class SelfResolver < FieldResolver
      #: (Executor::ExecutionField[untyped], ContextType) -> Array[untyped]
      def resolve(exec_field, _ctx)
        exec_field.map_objects(&:itself)
      end
    end

    #: [ContextType = GraphQL::Query::Context]
    class ValueResolver < FieldResolver
      #: untyped
      attr_reader :value

      #: (untyped) -> void
      def initialize(value)
        @value = value
      end

      #: (Executor::ExecutionField[untyped], ContextType) -> Array[untyped]
      def resolve(exec_field, _ctx)
        exec_field.resolve_all(@value)
      end
    end
  end
end
