# typed: true
# frozen_string_literal: true

require_relative "./executor/has_attributes"
require_relative "./executor/lazy_element"
require_relative "./executor/execution_scope"
require_relative "./executor/execution_field"
require_relative "./executor/execution_directive"
require_relative "./executor/abstract_execution_scope"
require_relative "./executor/execution_planner"
require_relative "./executor/input_formatter"
require_relative "./executor/error_formatter"
require_relative "./executor/path_formatter"

module GraphQL
  module BreadthExec
    class Executor
      #: type type_resolver = ^(untyped, GraphQL::Query::Context) -> singleton(GraphQL::Schema::Member)?
      #: type resolver = FieldResolver[untyped] | DirectiveResolver | type_resolver

      EMPTY_ARRAY = [].freeze
      EMPTY_OBJECT = {}.freeze
      UNDEFINED = Util::NilLike.new("undefined")
      EMPTY_TIMER = 0.0

      #: GraphQL::Query
      attr_reader :query

      #: singleton(GraphQL::Schema)
      attr_reader :schema

      #: variables_hash
      attr_reader :provided_variables

      #: GraphQL::Query::Context
      attr_reader :context

      #: InputFormatter
      attr_reader :input

      #: Hash[String, Hash[String, resolver]]
      attr_reader :resolvers

      #: ExecutionPlanner
      attr_reader :planner

      #: Hash[untyped, singleton(GraphQL::Schema::Object)]?
      attr_reader :abstract_result_types

      #: (
      #|   singleton(GraphQL::Schema),
      #|   String | GraphQL::Language::Nodes::Document,
      #|   ?resolvers: Hash[String, Hash[String, resolver]],
      #|   ?root_object: untyped,
      #|   ?variables: Hash[String | Symbol, untyped],
      #|   ?context: Hash[String | Symbol, untyped],
      #|   ?tracers: Array[Tracer],
      #|   ?authorization: singleton(Authorization),
      #| ) -> void
      def initialize(schema, document, resolvers: EMPTY_OBJECT, root_object: nil, variables: {}, context: {}, tracers: [], authorization: Authorization)
        @provided_variables = variables.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
        @schema = schema
        @resolvers = resolvers
        @query = GraphQL::Query.new(schema, document: document, variables: @provided_variables, context: context) # << for schema reference
        @context = @query.context
        @input = InputFormatter.new(@context)
        @planner = ExecutionPlanner.new(executor: self, resolvers: @resolvers)
        @authorization = authorization.new
        @document = document
        @root_object = root_object
        @tracers = tracers
        @result = {}
        @data = {}
        @errors = []
        @exec_queue = []
        @lazy_queue = []
        @invalidated_results = {}.compare_by_identity
        @abstract_result_types = nil
        @loader_cache = nil
        @paths = nil
        @executed = false
        @aborted = false
      end

      #: -> Hash[String, GraphQL::Language::Nodes::FragmentDefinition]
      def fragments
        @query.fragments
      end

      #: -> variables_hash
      def variables
        @input.variables
      end

      #: -> PathFormatter
      def paths
        @paths ||= PathFormatter.new
      end

      #: -> graphql_result
      def perform
        execute unless executed?
        @result
      end

      #: (singleton(LazyLoader), ?loader_args?) -> LazyLoader[untyped]
      def lazy_loader_for(loader_class, args = nil)
        @loader_cache ||= {}
        @loader_cache[[loader_class, args]] ||= args ? loader_class.new(**args) : loader_class.new
      end

      #: (Exception, ?exec_field: ExecutionField[untyped]?) -> ExecutionError
      def handle_or_reraise(original_error, exec_field: nil)
        case original_error
        when ExecutionError, GraphQL::ExecutionError
          ExecutionError.from(original_error, exec_field:)
        else
          raise original_error if original_error.equal?(@raised_exception)

          handled_error = begin
            handler = Execution::Errors.find_handler_for(@schema, original_error.class)

            raise original_error unless handler

            # Breadth execution does not support "current object" because field errors may span many objects.
            handler[:handler].call(original_error, nil, exec_field&.arguments, context, exec_field&.definition)
          rescue ExecutionError, GraphQL::ExecutionError => error
            error
          rescue Exception => exception
            @raised_exception = exception
            @tracers.each { _1.on_exception(exception, @context, exec_field:) }
            raise exception
          end
          ExecutionError.from(handled_error, exec_field:, cause: original_error)
        end
      end

      #: (ExecutionError, ?untyped?, ?exec_field: ExecutionField[untyped]?) -> ExecutionError
      def add_error(error, result = nil, exec_field: nil)
        error = exec_field ? ExecutionError.from(error, exec_field:) : error

        if exec_field
          current_type = exec_field.type
          current_type = current_type.of_type while current_type.list? || (current_type.non_null? && current_type.of_type.list?)
          error = invalidate_non_null_value(exec_field, current_type, error) if current_type.non_null?
        end

        @invalidated_results[result || error] = error
        error
      end

      #: -> Integer
      def error_count
        @invalidated_results.size
      end

      #: -> ErrorFormatter
      def error_result_formatter
        @error_result_formatter ||= ErrorFormatter.new(
          executor: self,
          invalidated_results: @invalidated_results,
          abstract_result_types: @abstract_result_types || EMPTY_OBJECT,
        )
      end

      #: -> bool
      def aborted?
        @aborted
      end

      #: -> bool
      def executed?
        @executed
      end

      private

      #: -> graphql_result
      def execute
        @executed = true

        # there is no result data until execution starts
        execution_state = { state: :not_started }

        start_time = EMPTY_TIMER
        unless @tracers.empty?
          start_time = timer
          @tracers.each { _1.start(self, @context) }
        end

        # reference selected operation first to trigger AST evaluation
        operation = @query.selected_operation

        if !@context.errors.empty?
          # Return any parsing errors
          return build_result(errors: @context.errors.map(&:to_h))
        end

        begin
          @input.coerce_variable_values(operation.variables, @query.provided_variables || EMPTY_OBJECT)
        rescue InputValidationErrorSet => e
          GraphQL::BreadthExec.report_error(e)
        end

        execute_with_directives(@planner.root_directives_for_operation(operation)) do
          begin
            execution_state[:state] = :started
            exec_start_time = EMPTY_TIMER
            unless @tracers.empty?
              exec_start_time = timer
              @tracers.each { _1.before_execute(self, @context) }
            end

            root_scopes = begin
              @planner.root_scopes_for_operation(operation, root_object: @root_object, result: @data)
            rescue OperationTypeUnsupportedError => op_err
              return build_result(errors: [op_err.to_h])
            end

            @planner.plan_scopes(root_scopes).each do |exec_scope|
              @exec_queue << exec_scope

              # Process eager scopes, then process resulting lazy fields
              # Work is always dequeued for processing to maintain a clean queue state
              until aborted? || (@exec_queue.empty? && @lazy_queue.empty?)
                if !@exec_queue.empty?
                  exec_scope = @exec_queue.shift #: as !nil
                  execute_scope(exec_scope)
                else
                  lazy_elements = @lazy_queue.shift(@lazy_queue.length)
                  execute_lazy(lazy_elements)
                end
              end
            end

            unless @tracers.empty?
              @tracers.each { _1.before_format_errors(self, @context) }
            end

            unless @invalidated_results.empty?
              root_type = @planner.root_type_for_operation(operation.operation_type)
              root_selections = operation.selections
              @data, @errors = error_result_formatter.format_object(root_type, root_selections, @data)
            end
            # once execution has completed, result data is the formatted result payload
            execution_state[:state] = :completed
          rescue Exception => ex
            raise ex
          ensure
            unless @tracers.empty?
              duration = timer(exec_start_time)
              @tracers.each { _1.after_execute(self, @context, duration:) }
            end
          end
        end

        build_result(data: execution_state[:state] == :completed ? @data : UNDEFINED, errors: @errors)
      rescue StandardError => e
        errors = [] #: Array[error_hash]
        handle_or_reraise(e).each { |ex| errors << ex.to_h }
        state = execution_state&.[](:state)
        data = if state == :completed
          @data
        elsif state == :started
          nil
        else
          UNDEFINED
        end
        build_result(data:, errors:)
      ensure
        unless @tracers.empty?
          duration = timer(start_time)
          @tracers.each { _1.finish(self, @context, duration:) }
        end
      end

      #: (
      #|   Array[ExecutionDirective],
      #|   ?current_field: ExecutionField[untyped]?,
      #|   ?at: Integer,
      #| ) { () -> untyped } -> untyped
      def execute_with_directives(exec_directives, current_field: nil, at: 0, &block)
        while at < exec_directives.size
          exec_directive = exec_directives[at]

          if exec_directive.resolver.applies?(exec_directive, current_field)
            exec_directive.validate!

            if exec_directive.resolver.wraps?
              return exec_directive.resolver.resolve(exec_directive, @context, current_field: current_field) do
                execute_with_directives(exec_directives, current_field: current_field, at: at + 1, &block)
              end
            else
              exec_directive.resolver.resolve(exec_directive, @context, current_field: current_field)
            end
          end

          at += 1
        end

        yield
      end

      #: (ExecutionScope) -> void
      def execute_scope(exec_scope)
        return if exec_scope.objects.empty?
        raise StandardError, "Cannot re-execute #{exec_scope.inspect}" if exec_scope.executed?

        begin
          unless exec_scope.has_authorized_objects?
            if @authorization.authorize_objects_in_scope?(exec_scope, @context)
              authorize_scope_objects(exec_scope, @authorization.unauthorized_object_indices(exec_scope, @context))
            else
              authorize_scope_objects(exec_scope, {})
            end

            return unless exec_scope.has_authorized_objects?
          end

          exec_scope.preload!
          if exec_scope.lazy_preloads?
            @lazy_queue << exec_scope
            return
          end
        rescue StandardError => e
          scope_error = handle_or_reraise(e, exec_field: exec_scope.parent_field)
          exec_scope.results.each { add_error(scope_error, _1, exec_field: exec_scope.parent_field) }
          exec_scope.abort!
          return
        end

        exec_scope.lazy_state_locked!
        exec_scope.executed = true

        unless @authorization.authorized_type?(exec_scope.parent_type, @context, exec_field: exec_scope.parent_field)
          parent_field = exec_scope.parent_field
          error = parent_field ? FieldAuthorizationError.new(exec_field: parent_field) : ExecutionError.new(FieldAuthorizationError::MESSAGE)
          exec_scope.results.each { add_error(error, _1, exec_field: parent_field) }
          return
        end

        exec_scope.fields.each_value do |exec_field|
          execute_field(exec_field) unless exec_field.scope.aborted?
        end
      end

      #: (ExecutionScope, invalidated_indices) -> ExecutionScope
      def authorize_scope_objects(exec_scope, invalidated_indices)
        unless invalidated_indices.empty?
          parent_field = exec_scope.parent_field
          invalidated_indices.keys.sort.reverse_each do |index|
            exec_scope.objects.delete_at(index)
            result = exec_scope.results.delete_at(index)
            error = invalidated_indices[index]

            error = if parent_field && !error.equal?(UNREPORTED_ERROR)
              FieldAuthorizationError.from(error, exec_field: parent_field)
            else
              ExecutionError.from(error || FieldAuthorizationError::MESSAGE)
            end

            add_error(error, result, exec_field: parent_field)
          end
        end

        exec_scope.objects.freeze
        exec_scope.results.freeze
        exec_scope
      end

      #: (Array[LazyElement]) -> void
      def execute_lazy(lazy_elements)
        aborted_status_cache = Hash.new { |h, exec_scope| h[exec_scope] = exec_scope.aborted_subtree? }.compare_by_identity
        pending_loaders = (@loader_cache || EMPTY_OBJECT).each_value.reject { _1.promised.empty? }

        if pending_loaders.empty?
          raise ImplementationError, "Lazy #{lazy_elements.first&.inspect} produced a promise without a loader"
        end

        pending_loaders.each do |loader|
          loader_elements = loader.promised.map(&:element)
          all_aborted = loader_elements.all? do |element|
            aborted_status_cache[element.is_a?(ExecutionField) ? element.scope : element]
          end

          if all_aborted
            loader.reset!
            next
          end

          begin
            loader.execute!(@context)
          rescue StandardError => e
            handled_error = handle_or_reraise(e)
            loader_elements.each do |element|
              case element
              when ExecutionField
                field_error = ExecutionError.from(handled_error, exec_field: element)
                element.result = element.resolve_all(field_error)
              when ExecutionScope
                scope_error = ExecutionError.from(handled_error, exec_field: element.parent_field)
                element.results.each { add_error(scope_error, _1, exec_field: element.parent_field) }
                element.abort!
              end
            end
          end
        end

        aborted_status_cache.clear
        lazy_elements.each do |element|
          case element
          when ExecutionField
            next if aborted_status_cache[element.scope]

            if element.has_result?
              resume_lazy_field_result(element)
            else
              resume_lazy_field_execute(element)
            end
          when ExecutionScope
            next if aborted_status_cache[element]

            resume_lazy_scope_execute(element)
          end
        end
      end

      #: (ExecutionScope) -> void
      def resume_lazy_scope_execute(exec_scope)
        begin
          exec_scope.preload_promises.reject! { promise_resolved?(_1, element: exec_scope) }
        rescue ExecutionError => e
          exec_scope.results.each { add_error(e, _1, exec_field: exec_scope.parent_field) }
          exec_scope.abort!
          return
        end

        execute_scope(exec_scope)
      end

      #: (ExecutionField[untyped]) -> void
      def resume_lazy_field_execute(exec_field)
        begin
          exec_field.preload_promises.reject! { promise_resolved?(_1, element: exec_field) }
        rescue ExecutionError => e
          exec_field.result = exec_field.resolve_all(e)
        end

        if exec_field.has_result?
          build_field_result(exec_field, exec_field.result)
        else
          execute_field(exec_field)
        end
      end

      #: (ExecutionField[untyped]) -> void
      def resume_lazy_field_result(exec_field)
        if exec_field.lazy_result?
          begin
            promise = exec_field.result
            if promise_resolved?(promise, element: exec_field)
              exec_field.result = promise.value
            end
          rescue ExecutionError => e
            exec_field.result = exec_field.resolve_all(e)
          end
        end

        if exec_field.lazy_result?
          @lazy_queue << exec_field
        else
          build_field_result(exec_field, exec_field.result)
        end
      end

      #: (ExecutionPromise, element: LazyElement) -> bool
      def promise_resolved?(promise, element:)
        return true if promise.resolved?

        if promise.rejected?
          reason = promise.reason
          unless reason.is_a?(StandardError)
            reason = UnknownLazyRejectionError.new("Lazy #{element.inspect} was rejected for an unknown reason: #{reason}")
          end

          exec_field = case element
          when ExecutionField
            element
          when ExecutionScope
            element.parent_field
          end

          raise handle_or_reraise(reason, exec_field:)
        end

        false
      end

      #: (ExecutionField[untyped]) -> void
      def execute_field(exec_field)
        begin
          exec_field.preload!
        rescue StandardError => e
          field_error = handle_or_reraise(e, exec_field:)
          exec_field.result = exec_field.resolve_all(field_error)
          build_field_result(exec_field, exec_field.result)
          return
        end

        if exec_field.lazy_preloads?
          @lazy_queue << exec_field
          build_field_placeholder(exec_field)
          return
        end

        parent_type = exec_field.scope.parent_type
        field_name = exec_field.name
        parent_objects = exec_field.scope.objects

        begin
          @tracers.each { _1.before_resolve_field(parent_type, field_name, parent_objects.length, @context) }
          exec_field.lazy_state_executing!
          exec_field.validate!
          pre_authorized = @authorization.authorized_field?(exec_field, @context)
          pre_authorized &&= @authorization.authorized_type?(exec_field.type.unwrap, @context, exec_field: exec_field)

          # each branch must assign `exec_field.result` to make it available in the final ensure block
          if !pre_authorized
            exec_field.result = exec_field.resolve_all(FieldAuthorizationError.new(exec_field: exec_field))
          elsif exec_field.directives.empty?
            exec_field.result = exec_field.resolver.resolve_field(exec_field, @context)
          else
            execute_with_directives(exec_field.directives, current_field: exec_field) do
              exec_field.result = exec_field.resolver.resolve_field(exec_field, @context)
            end
          end
        rescue StandardError => e
          error = handle_or_reraise(e, exec_field: exec_field)
          @errors << error if error.base_error?
          exec_field.result = Array.new(parent_objects.length, error)
        ensure
          @tracers.each { _1.after_resolve_field(parent_type, field_name, parent_objects.length, @context) }
        end

        if exec_field.lazy_result?
          @lazy_queue << exec_field
          build_field_placeholder(exec_field)
        else
          build_field_result(exec_field, exec_field.result)
        end
      end

      #: (ExecutionField[untyped]) -> void
      def build_field_placeholder(exec_field)
        field_key = exec_field.key
        scope_results = exec_field.scope.results
        i = 0
        while i < scope_results.size
          # build a field key to hold the order position of lazy results
          scope_results[i][field_key] = UNDEFINED
          i += 1
        end
      end

      #: (ExecutionField[untyped], Array[untyped]) -> void
      def build_field_result(exec_field, resolved_objects)
        exec_field.lazy_state_locked!

        start_time = EMPTY_TIMER
        unless @tracers.empty?
          start_time = timer
          @tracers.each { _1.before_build_field_result(exec_field, @context) }
        end

        parent_objects = exec_field.scope.objects
        parent_results = exec_field.scope.results
        field_key = exec_field.key
        field_type = exec_field.type
        return_type = field_type.unwrap

        if resolved_objects.length != parent_objects.length
          handle_or_reraise(ResultCountMismatchError.new(
            exec_field: exec_field,
            expected_count: parent_objects.length,
            actual_count: resolved_objects.length,
          ))
          resolved_objects = exec_field.resolve_all(nil)
        end

        if return_type.kind.composite?
          # build results with child selections
          next_objects = []
          next_results = []
          i = 0
          while i < resolved_objects.length
            object = resolved_objects[i]
            parent_results[i][field_key] = build_and_flatmap_composite_result(exec_field, field_type, object, next_objects, next_results)
            i += 1
          end

          if return_type.kind.abstract?
            build_abstract_scopes(exec_field, return_type, next_objects, next_results)
          else
            next_scope = @planner.planned_scope_for(exec_field)
            if next_scope
              next_scope.objects.replace(next_objects)
              next_scope.results.replace(next_results)
              @exec_queue << next_scope if next_objects.length.positive?
            end
          end
        else
          # build leaf results
          i = 0
          while i < resolved_objects.length
            val = resolved_objects[i]
            parent_results[i][field_key] = build_leaf_result(exec_field, field_type, val)
            i += 1
          end
        end
      rescue StandardError => e
        field_error = handle_or_reraise(e, exec_field: exec_field)
        exec_field.scope.results.each { _1[exec_field.key] = field_error }
        add_error(field_error)
      ensure
        unless @tracers.empty?
          duration = timer(start_time)
          @tracers.each { _1.after_build_field_result(exec_field, @context, duration:) }
        end
      end

      #: (
      #|   ExecutionField[untyped] exec_field,
      #|   untyped current_type,
      #|   untyped object,
      #|   Array[untyped] next_objects,
      #|   Array[Hash[String, untyped]] next_results,
      #| ) -> untyped
      def build_and_flatmap_composite_result(exec_field, current_type, object, next_objects, next_results)
        if object.nil? || object.is_a?(StandardError)
          build_missing_value(exec_field, current_type, object)
        elsif current_type.list?
          unless object.is_a?(Array)
            raise InvalidListResultError.new(exec_field:, result_type: object.class)
          end

          current_type = Util.unwrap_non_null(current_type)

          object.map do |src|
            build_and_flatmap_composite_result(exec_field, current_type.of_type, src, next_objects, next_results)
          end
        else
          next_objects << object
          next_results << {}
          next_results.last
        end
      end

      #: (
      #|   ExecutionField[untyped] exec_field,
      #|   untyped current_type,
      #|   untyped val,
      #| ) -> untyped
      def build_leaf_result(exec_field, current_type, val)
        if val.nil? || val.is_a?(StandardError)
          build_missing_value(exec_field, current_type, val)
        elsif current_type.list?
          unless val.is_a?(Array)
            raise InvalidListResultError.new(exec_field:, result_type: val.class)
          end

          current_type = Util.unwrap_non_null(current_type)

          val.map { build_leaf_result(exec_field, current_type.of_type, _1) }
        else
          begin
            unwrapped_type = current_type.unwrap
            coerced_val = unwrapped_type.coerce_result(val, @context)
            return coerced_val unless coerced_val.nil?

            build_missing_value(exec_field, current_type, nil)
          rescue StandardError => e
            field_error = handle_or_reraise(e, exec_field:)
            build_missing_value(exec_field, current_type, field_error)
          end
        end
      end

      #: (
      #|   ExecutionField[untyped] exec_field,
      #|   untyped current_type,
      #|   StandardError? val,
      #| ) -> untyped
      def build_missing_value(exec_field, current_type, val)
        val = invalidate_non_null_value(exec_field, current_type, val) if current_type.non_null?

        if val
          val = handle_or_reraise(val, exec_field:)
          add_error(val)
        end

        val
      end

      #: (
      #|   ExecutionField[untyped] exec_field,
      #|   untyped current_type,
      #|   StandardError? val,
      #| ) -> StandardError
      def invalidate_non_null_value(exec_field, current_type, val)
        propagate_null!(exec_field)

        if val.nil? || val.equal?(UNREPORTED_ERROR)
          list_item = !!(exec_field.type.list? && !exec_field.type.equal?(current_type))
          val = InvalidNullError.new(exec_field:, list_item:)

          err_class = exec_field.scope.parent_type.const_get(:InvalidNullError) # rubocop:disable Sorbet/ConstantsFromStrings
          type_error = err_class.new(exec_field.scope.parent_type, exec_field.definition, exec_field.nodes.first)
          @schema.type_error(type_error, @context)
        end

        val
      end

      #: (ExecutionField[untyped]) -> void
      def propagate_null!(exec_field)
        return if exec_field.scope.aborted? || !exec_field.propagates_null?

        # Walk the tree to determine the highest contiguous non-null depth, and the highest list depth.
        # We can ONLY abort breadth resolvers when one of the following happens:
        # 1. null propagation reaches the root scope (total loss)
        # 2. there are no lists in the tree (no objects will share breadth resolvers)
        # 3. all lists in the tree are invalidated (all objects sharing a resolver are eliminated)
        current_exec_field = exec_field #: ExecutionField[untyped]?
        propagating = !!exec_field.propagates_null?
        highest_nulled_depth = exec_field.scope.depth
        highest_list_depth = Integer(-1)

        while current_exec_field
          if current_exec_field.propagates_null? && propagating
            highest_nulled_depth = current_exec_field.scope.depth
          else
            propagating = false
          end

          if current_exec_field.type.list?
            highest_list_depth = Integer(current_exec_field.scope.depth)
          end

          current_exec_field = current_exec_field.scope.parent_field
        end

        if highest_nulled_depth.zero?
          # Mark the entire executor as aborted when non-null propagation hits the top.
          # This prevents subsequent isolated root scopes (mutations) from running.
          @aborted = true
        elsif highest_list_depth.negative? || highest_nulled_depth <= highest_list_depth
          # Abort all non-null ancestor scopes that meet or exceed the highest-level list.
          # (all lists must be completely invalidated, or else remain alive).
          abort_field = exec_field #: ExecutionField[untyped]?
          while abort_field && highest_nulled_depth <= abort_field.scope.depth
            abort_field.scope.abort!
            abort_field = abort_field.scope.parent_field
          end

          # Purge all aborted work from the queue
          @exec_queue.reject!(&:aborted_subtree?)
        end
      end

      #: (
      #|   ExecutionField[untyped] exec_field,
      #|   singleton(GraphQL::Schema::Member) return_type,
      #|   Array[untyped] next_objects,
      #|   Array[Hash[String, untyped]] next_results,
      #| ) -> void
      def build_abstract_scopes(exec_field, return_type, next_objects, next_results)
        @abstract_result_types ||= {}.compare_by_identity
        abstract_type = return_type
        type_resolver = @resolvers.dig(abstract_type.graphql_name, "__type__") #: as type_resolver?
        possible_types = @context.types.possible_types(abstract_type).to_set

        next_objects_by_type = Hash.new { |h, k| h[k] = [] }.compare_by_identity
        next_results_by_type = Hash.new { |h, k| h[k] = [] }.compare_by_identity

        i = 0
        while i < next_objects.length
          object = next_objects[i]

          object_type = if type_resolver
            type_resolver.call(object, @context)
          else
            resolved_type, resolved_object = @query.resolve_type(abstract_type, object)
            if resolved_type && @schema.lazy?(resolved_type)
              resolved_type, resolved_object = @schema.sync_lazy(resolved_type)
            end
            if resolved_type.nil? || !possible_types.include?(resolved_type)
              err_class = abstract_type.const_get(:UnresolvedTypeError)
              type_error = err_class.new(resolved_object, exec_field.definition, abstract_type, resolved_type, possible_types)
              @schema.type_error(type_error, @context)
              raise ImplementationError, "Failed to resolve a type for object in `#{abstract_type.graphql_name}.#{exec_field.name}`"
            end

            if !object.equal?(resolved_object)
              next_objects[i] = resolved_object
              object = resolved_object
            end
            resolved_type
          end

          next_objects_by_type[object_type] << object
          result = next_results[i]
          next_results_by_type[object_type] << result
          @abstract_result_types[result] = object_type
          i += 1
        end

        scopes = []
        abstract_scope = AbstractExecutionScope.new(parent_type: return_type, parent_field: exec_field, scopes: scopes)
        next_objects_by_type.each do |impl_type, impl_type_objects|
          scopes << ExecutionScope.new(
            executor: self,
            abstraction: abstract_scope,
            parent_field: exec_field,
            parent_type: impl_type,
            selections: exec_field.selections,
            objects: impl_type_objects,
            results: next_results_by_type[impl_type],
          )
        end

        @exec_queue.concat(@planner.plan_scopes(scopes))
      end

      #: (?data: Util::NilLike | graphql_result | nil, ?errors: Array[error_hash]) -> graphql_result
      def build_result(data: UNDEFINED, errors: EMPTY_ARRAY)
        # Truncate errors but preserve GraphQL-Ruby's validation error limit message when present.
        # For execution errors, add our own message to inform truncation.
        if @max_reported_errors && errors.size > @max_reported_errors
          unless errors.last["message"]&.include?("error limit reached")
            errors = errors.take(@max_reported_errors)
            errors << { "message" => "Too many execution errors, max error limit reached. Results truncated" }
          end
        end

        # install errors first to surface at the top
        @result["errors"] = errors unless errors.empty?

        # only install data when execution has run and generated (possibly partial) results
        @result["data"] = data unless data.equal?(UNDEFINED)

        # collect extensions that have already been added to the result by tracers,
        # and check for extensions defined through `@context.response_extensions`.
        # extensions always get re-added to the result as the final key
        result_extensions = @result.delete("extensions")
        has_context_extensions = @context.namespace?(:__query_result_extensions__)
        if result_extensions || has_context_extensions
          result_extensions ||= {}
          result_extensions.merge!(@context.namespace(:__query_result_extensions__)) if has_context_extensions
          @result["extensions"] = Util.deep_copy(result_extensions, stringify_keys: true)
        end

        @result
      end

      #: (?Float?) -> Float
      def timer(start_time = nil)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
        start_time.nil? ? now.to_f : now - start_time
      end
    end
  end
end
