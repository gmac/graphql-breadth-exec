# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::TracersTest < Minitest::Test
  class BoomResolver < GraphQL::BreadthExec::FieldResolver
    def resolve(_exec_field, _context)
      raise StandardError, "boom"
    end
  end

  class ExtensionTracer < GraphQL::BreadthExec::Tracer
    def before_execute(executor, _context)
      executor.response_extensions[:trace] = { started: true }
    end

    def after_execute(executor, _context, duration:)
      executor.response_extensions[:trace][:finished] = true
    end
  end

  class TestTracer < GraphQL::BreadthExec::Tracer
    attr_reader :start_calls, :finish_calls, :finish_durations
    attr_reader :before_execute_calls, :after_execute_calls, :execute_durations
    attr_reader :before_format_errors_calls
    attr_reader :before_scope_calls
    attr_reader :before_resolve_field_calls, :after_resolve_field_calls, :resolve_durations
    attr_reader :before_build_field_result_calls, :after_build_field_result_calls, :build_field_result_durations
    attr_reader :before_lazy_set_calls, :after_lazy_set_calls, :lazy_set_durations
    attr_reader :before_abstract_scope_calls
    attr_reader :on_exception_calls

    def initialize
      super()
      @start_calls = []
      @finish_calls = []
      @finish_durations = []
      @before_execute_calls = []
      @after_execute_calls = []
      @execute_durations = []
      @before_format_errors_calls = []
      @before_scope_calls = []
      @before_resolve_field_calls = []
      @after_resolve_field_calls = []
      @resolve_durations = []
      @before_build_field_result_calls = []
      @after_build_field_result_calls = []
      @build_field_result_durations = []
      @before_lazy_set_calls = []
      @after_lazy_set_calls = []
      @lazy_set_durations = []
      @before_abstract_scope_calls = []
      @on_exception_calls = []
    end

    def start(executor, _context)
      @start_calls << executor
    end

    def finish(executor, _context, duration:)
      @finish_calls << executor
      @finish_durations << duration
    end

    def before_execute(executor, _context)
      @before_execute_calls << executor
    end

    def after_execute(executor, _context, duration:)
      @after_execute_calls << executor
      @execute_durations << duration
    end

    def before_format_errors(executor, _context)
      @before_format_errors_calls << executor
    end

    def before_scope(exec_scope, _context)
      @before_scope_calls << exec_scope.parent_type.graphql_name
    end

    def before_resolve_field(exec_field, _context)
      @before_resolve_field_calls << [exec_field.parent_type.graphql_name, exec_field.name, exec_field.objects.length]
    end

    def after_resolve_field(exec_field, _context, duration:)
      @after_resolve_field_calls << [exec_field.parent_type.graphql_name, exec_field.name, exec_field.objects.length]
      @resolve_durations << duration
    end

    def before_lazy_set(loader, elements, _context)
      @before_lazy_set_calls << [loader.class, elements.map(&:class)]
    end

    def after_lazy_set(loader, elements, _context, duration:)
      @after_lazy_set_calls << [loader.class, elements.map(&:class)]
      @lazy_set_durations << duration
    end

    def before_abstract_scope(abstract_scope, _context)
      @before_abstract_scope_calls << abstract_scope.parent_type.graphql_name
    end

    def before_build_field_result(exec_field, _context)
      @before_build_field_result_calls << [exec_field.parent_type.graphql_name, exec_field.name, exec_field.objects.length]
    end

    def after_build_field_result(exec_field, _context, duration:)
      @after_build_field_result_calls << [exec_field.parent_type.graphql_name, exec_field.name, exec_field.objects.length]
      @build_field_result_durations << duration
    end

    def on_exception(exception, _context, exec_field: nil)
      @on_exception_calls << [exception, exec_field&.name]
    end
  end

  def setup
    @tracer = TestTracer.new
    @document = %|{
      products(first: 1) {
        nodes { id }
      }
    }|
    @source = {
      "products" => {
        "nodes" => [{ "id" => "1" }],
      },
    }
  end

  def test_calls_start_finish_and_execute_hooks
    result = breadth_exec(@document, @source, tracers: [@tracer])

    assert_equal @source, result["data"]
    assert_equal 1, @tracer.start_calls.size
    assert_equal 1, @tracer.finish_calls.size
    assert_equal 1, @tracer.before_execute_calls.size
    assert_equal 1, @tracer.after_execute_calls.size
    assert @tracer.start_calls.all? { _1.is_a?(GraphQL::BreadthExec::Executor) }
    assert @tracer.finish_calls.all? { _1.is_a?(GraphQL::BreadthExec::Executor) }
    assert @tracer.finish_durations.all? { _1.is_a?(Float) && _1 >= 0 }
    assert @tracer.execute_durations.all? { _1.is_a?(Float) && _1 >= 0 }
  end

  def test_calls_field_resolve_hooks_with_parent_type_field_name_and_object_count
    result = breadth_exec(@document, @source, tracers: [@tracer])

    assert_equal @source, result["data"]
    assert_equal(
      [
        ["Query", "products", 1],
        ["ProductConnection", "nodes", 1],
        ["Product", "id", 1],
      ],
      @tracer.before_resolve_field_calls,
    )
    assert_equal @tracer.before_resolve_field_calls, @tracer.after_resolve_field_calls
    assert @tracer.resolve_durations.all? { _1.is_a?(Float) && _1 >= 0 }
  end

  def test_calls_scope_hooks
    result = breadth_exec(@document, @source, tracers: [@tracer])

    assert_equal @source, result["data"]
    assert_equal(
      ["Query", "ProductConnection", "Product"],
      @tracer.before_scope_calls,
    )
  end

  def test_calls_field_result_build_hooks
    result = breadth_exec(@document, @source, tracers: [@tracer])

    assert_equal @source, result["data"]
    assert_equal(
      [
        ["Query", "products", 1],
        ["ProductConnection", "nodes", 1],
        ["Product", "id", 1],
      ],
      @tracer.before_build_field_result_calls,
    )
    assert_equal @tracer.before_build_field_result_calls, @tracer.after_build_field_result_calls
    assert @tracer.build_field_result_durations.all? { _1.is_a?(Float) && _1 >= 0 }
  end

  def test_calls_before_format_errors
    breadth_exec(@document, @source, tracers: [@tracer])

    assert_equal 1, @tracer.before_format_errors_calls.size
    assert @tracer.before_format_errors_calls.all? { _1.is_a?(GraphQL::BreadthExec::Executor) }
  end

  def test_tracers_can_install_response_extensions
    result = breadth_exec(@document, @source, tracers: [ExtensionTracer.new])

    assert_equal(
      {
        "trace" => {
          "started" => true,
          "finished" => true,
        },
      },
      result["extensions"],
    )
  end

  def test_calls_on_exception_for_unhandled_errors
    resolvers = BREADTH_RESOLVERS.merge(
      "Query" => BREADTH_RESOLVERS.fetch("Query").merge(
        "products" => BoomResolver.new,
      ),
    )

    assert_raises(StandardError) do
      GraphQL::BreadthExec::Executor.new(
        SCHEMA,
        GraphQL.parse("{ products(first: 1) { nodes { id } } }"),
        resolvers: resolvers,
        root_object: @source,
        tracers: [@tracer],
      ).result
    end

    assert_equal 1, @tracer.on_exception_calls.size
    exception, field_name = @tracer.on_exception_calls.first
    assert_instance_of StandardError, exception
    assert_equal "products", field_name
  end
end
