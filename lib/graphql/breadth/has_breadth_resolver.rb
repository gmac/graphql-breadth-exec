# typed: true
# frozen_string_literal: true

module GraphQL
  module Breadth
    module HasBreadthResolver
      module Field
        CORRECT_USAGE = "HasBreadthResolver::Field must be included in GraphQL::Schema::Field"

        class << self
          #: (Class) -> void
          def included(base)
            unless base <= GraphQL::Schema::Field
              raise ImplementationError, CORRECT_USAGE
            end
          end

          #: (Class) -> void
          def extended(_base)
            raise ImplementationError, CORRECT_USAGE
          end
        end

        #: FieldResolver?
        attr_reader :breadth_resolver

        #: -> (String | Symbol)
        def original_name
          super
        end

        #: (Symbol | FieldResolver | singleton(FieldResolver) | nil) -> void
        def breadth_resolver=(value)
          @breadth_resolver = case value
          when Symbol
            case value
            when :method
              MethodResolver.new(original_name)
            when :hash_key_symbol
              HashKeyResolver.new(original_name)
            when :hash_key_string
              HashKeyResolver.new(original_name.to_s)
            when :itself
              SelfResolver.new
            else
              Kernel.raise ImplementationError, "Invalid breadth resolver keyword: #{value}. Expected one of method, hash_key_symbol, hash_key_string, itself."
            end
          when Class
            value.new
          else
            value
          end
        end
      end

      module Directive
        CORRECT_USAGE = "HasBreadthResolver::Directive must be extended in GraphQL::Schema::Directive"

        class << self
          #: (Class) -> void
          def included(_base)
            raise ImplementationError, CORRECT_USAGE
          end

          #: (Class) -> void
          def extended(base)
            unless base <= GraphQL::Schema::Directive
              raise ImplementationError, CORRECT_USAGE
            end
          end
        end

        #: DirectiveResolver?
        attr_accessor :breadth_resolver

        #: (untyped) -> void
        def inherited(base)
          super
          base.breadth_resolver = breadth_resolver
        end
      end
    end
  end
end
