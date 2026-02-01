# frozen_string_literal: true

module GraphQL::BreadthExec
  class Executor
    class Authorization
      class << self
        def can_access_type?(type, context)
          true
        end

        def can_access_field?(type, field_name, context)
          true
        end

        def can_access_object?(type, object, context)
          true
        end
      end
    end
  end
end
