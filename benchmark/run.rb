# frozen_string_literal: true
#
require "debug"
require "graphql"
require "graphql/batch"
require "graphql/breadth_exec"

require "benchmark/ips"
require "memory_profiler"
require_relative '../test/fixtures'

class GraphQLBenchmark
  module NoopAnalysisEngine
    module_function

    def analyze_multiplex(_multiplex, _analyzers)
      []
    end

    def analyze_query(_query, _analyzers, multiplex_analyzers: [])
      []
    end
  end

  GRAPHQL_EXECUTION_OPTIONS = {
    validate: false,
  }.freeze

  DOCUMENT = GraphQL.parse(BASIC_DOCUMENT)
  CARDINAL_SCHEMA = SCHEMA
  CARDINAL_TRACER = GraphQL::BreadthExec::Tracer.new
  RESOLVE_BATCH_OBJECT_COUNT = 1_000
  RESOLVE_BATCH_DOCUMENT = GraphQL.parse(%|{
    widgets {
      id
      title
      score
    }
  }|)
  LAZY_FIELD_BATCH_DOCUMENT = GraphQL.parse(%|{
    widgets {
      title
    }
  }|)

  RESOLVE_BATCH_SDL = %|
    type Widget {
      id: ID!
      title: String!
      score: Int!
    }

    type Query {
      widgets: [Widget!]!
    }
  |

  RESOLVE_BATCH_DATA = {
    "widgets" => Array.new(RESOLVE_BATCH_OBJECT_COUNT) do |index|
      {
        "id" => index.to_s,
        "title" => "Widget #{index}",
        "score" => index,
      }
    end
  }.freeze

  RESOLVE_BATCH_RESOLVERS = {
    "Widget" => {
      "id" => GraphQL::BreadthExec::HashKeyResolver.new("id"),
      "title" => GraphQL::BreadthExec::HashKeyResolver.new("title"),
      "score" => GraphQL::BreadthExec::HashKeyResolver.new("score"),
    },
    "Query" => {
      "widgets" => GraphQL::BreadthExec::HashKeyResolver.new("widgets"),
    },
  }.freeze

  RESOLVE_BATCH_BREADTH_SCHEMA = GraphQL::Schema.from_definition(RESOLVE_BATCH_SDL)

  class NoopBreadthLazyLoader < GraphQL::BreadthExec::LazyLoader
    def map?
      true
    end

    def perform_map(keys, _context)
      keys
    end
  end

  class LazyHashKeyResolver < GraphQL::BreadthExec::FieldResolver
    def initialize(key)
      @key = key
    end

    def resolve(exec_field, _context)
      exec_field.lazy(
        loader_class: NoopBreadthLazyLoader,
        keys: exec_field.objects.map { _1.fetch(@key) },
      )
    end
  end

  LAZY_SCALAR_BREADTH_RESOLVERS = {
    "Widget" => {
      "id" => LazyHashKeyResolver.new("id"),
      "title" => LazyHashKeyResolver.new("title"),
      "score" => LazyHashKeyResolver.new("score"),
    },
    "Query" => {
      "widgets" => GraphQL::BreadthExec::HashKeyResolver.new("widgets"),
    },
  }.freeze

  class Schema < GraphQL::Schema
    lazy_resolve(Proc, :call)
  end

  class DataloaderSchema < GraphQL::Schema
    use GraphQL::Dataloader
  end

  class BatchLoaderSchema < GraphQL::Schema
    use GraphQL::Batch
  end

  class ClassicResolveBatchSchema < GraphQL::Schema
    class Widget < GraphQL::Schema::Object
      field :id, ID, null: false, hash_key: "id"
      field :title, String, null: false, hash_key: "title"
      field :score, Integer, null: false, hash_key: "score"
    end

    class Query < GraphQL::Schema::Object
      field :widgets, [Widget], null: false, hash_key: "widgets"
    end

    query(Query)
  end

  class LazyScalarBatchSchema < GraphQL::Schema
    use GraphQL::Batch

    class FieldLoader < GraphQL::Batch::Loader
      def initialize(field_name)
        @field_name = field_name
      end

      def perform(objects)
        objects.each { |object| fulfill(object, object.fetch(@field_name)) }
      end
    end

    class Widget < GraphQL::Schema::Object
      field :id, ID, null: false
      field :title, String, null: false
      field :score, Integer, null: false

      def id
        FieldLoader.for("id").load(object)
      end

      def title
        FieldLoader.for("title").load(object)
      end

      def score
        FieldLoader.for("score").load(object)
      end
    end

    class Query < GraphQL::Schema::Object
      field :widgets, [Widget], null: false, hash_key: "widgets"
    end

    query(Query)
  end

  class LazyScalarDataloaderSchema < GraphQL::Schema
    use GraphQL::Dataloader

    class FieldSource < GraphQL::Dataloader::Source
      def initialize(field_name)
        @field_name = field_name
      end

      def fetch(objects)
        objects.map { _1.fetch(@field_name) }
      end
    end

    class Widget < GraphQL::Schema::Object
      field :id, ID, null: false
      field :title, String, null: false
      field :score, Integer, null: false

      def id
        dataloader.with(FieldSource, "id").load(object)
      end

      def title
        dataloader.with(FieldSource, "title").load(object)
      end

      def score
        dataloader.with(FieldSource, "score").load(object)
      end
    end

    class Query < GraphQL::Schema::Object
      field :widgets, [Widget], null: false, hash_key: "widgets"
    end

    query(Query)
  end

  if defined?(GraphQL::Execution::Next)
    class ResolveBatchSchema < GraphQL::Schema
      use GraphQL::Execution::Next

      class Widget < GraphQL::Schema::Object
        field :id, ID, null: false, resolve_batch: true
        field :title, String, null: false, resolve_batch: true
        field :score, Integer, null: false, resolve_batch: true

        def self.id(objects, _context)
          objects.map { _1["id"] }
        end

        def self.title(objects, _context)
          objects.map { _1["title"] }
        end

        def self.score(objects, _context)
          objects.map { _1["score"] }
        end
      end

      class Query < GraphQL::Schema::Object
        field :widgets, [Widget], null: false, resolve_batch: true

        def self.widgets(objects, _context)
          objects.map { _1.fetch("widgets") }
        end
      end

      query(Query)
    end

    class LazyFieldNextBatchSchema < GraphQL::Schema
      use GraphQL::Execution::Next
      use GraphQL::Batch

      class FieldLoader < GraphQL::Batch::Loader
        def perform(objects)
          objects.each { |object| fulfill(object, object.fetch("title")) }
        end
      end

      class Widget < GraphQL::Schema::Object
        field :title, String, null: false, resolve_batch: true

        def self.title(objects, _context)
          objects.map { |object| FieldLoader.for.load(object) }
        end
      end

      class Query < GraphQL::Schema::Object
        field :widgets, [Widget], null: false, resolve_batch: true

        def self.widgets(objects, _context)
          objects.map { _1.fetch("widgets") }
        end
      end

      query(Query)
    end

    class LazyFieldNextDataloaderSchema < GraphQL::Schema
      use GraphQL::Execution::Next
      use GraphQL::Dataloader

      class FieldSource < GraphQL::Dataloader::Source
        def fetch(objects)
          objects.map { _1.fetch("title") }
        end
      end

      class Widget < GraphQL::Schema::Object
        field :title, String, null: false, resolve_batch: true

        def self.title(objects, context)
          context.dataloader.with(FieldSource).load_all(objects)
        end
      end

      class Query < GraphQL::Schema::Object
        field :widgets, [Widget], null: false, resolve_batch: true

        def self.widgets(objects, _context)
          objects.map { _1.fetch("widgets") }
        end
      end

      query(Query)
    end
  end

  GRAPHQL_GEM_SCHEMA = Schema.from_definition(SDL, default_resolve: GEM_RESOLVERS)
  GRAPHQL_GEM_LAZY_SCHEMA = Schema.from_definition(SDL, default_resolve: GEM_LAZY_RESOLVERS)
  GRAPHQL_GEM_DATALOADER_SCHEMA = DataloaderSchema.from_definition(SDL, default_resolve: GEM_DATALOADER_RESOLVERS)
  GRAPHQL_GEM_DATALOADER_SCHEMA.use(GraphQL::Dataloader)

  GRAPHQL_GEM_BATCH_LOADER_SCHEMA = BatchLoaderSchema.from_definition(SDL, default_resolve: GEM_BATCH_LOADER_RESOLVERS)
  GRAPHQL_GEM_BATCH_LOADER_SCHEMA.use(GraphQL::Batch)

  [
    GRAPHQL_GEM_SCHEMA,
    GRAPHQL_GEM_LAZY_SCHEMA,
    GRAPHQL_GEM_DATALOADER_SCHEMA,
    GRAPHQL_GEM_BATCH_LOADER_SCHEMA,
    ClassicResolveBatchSchema,
    LazyScalarBatchSchema,
    LazyScalarDataloaderSchema,
    (ResolveBatchSchema if defined?(ResolveBatchSchema)),
    (LazyFieldNextBatchSchema if defined?(LazyFieldNextBatchSchema)),
    (LazyFieldNextDataloaderSchema if defined?(LazyFieldNextDataloaderSchema)),
  ].compact.each do |schema|
    schema.analysis_engine = NoopAnalysisEngine
  end

  class << self
    def execute_graphql_ruby(schema, document:, root_value: nil)
      schema.execute(
        document: document,
        root_value: root_value,
        **GRAPHQL_EXECUTION_OPTIONS,
      )
    end

    def execute_graphql_ruby_next(schema, document:, root_value: nil)
      schema.execute_next(
        document: document,
        root_value: root_value,
        **GRAPHQL_EXECUTION_OPTIONS,
      )
    end

    def benchmark_execution
      default_data_sizes = "10, 100, 1000, 10000"
      sizes = ENV.fetch("SIZES", default_data_sizes).split(",").map(&:to_i)

      with_data_sizes(sizes) do |data_source, num_objects|
        Benchmark.ips do |x|
          x.report("graphql-ruby: #{num_objects} resolvers") do
            execute_graphql_ruby(GRAPHQL_GEM_SCHEMA, document: DOCUMENT, root_value: data_source)
          end

          x.report("graphql-cardinal #{num_objects} resolvers") do
            GraphQL::BreadthExec::Executor.new(
              SCHEMA,
              DOCUMENT,
              resolvers: BREADTH_RESOLVERS,
              root_object: data_source,
              tracers: [CARDINAL_TRACER],
            ).result
          end

          x.compare!
        end
      end
    end

    def benchmark_lazy_execution
      default_data_sizes = "10, 100, 1000, 10000"
      sizes = ENV.fetch("SIZES", default_data_sizes).split(",").map(&:to_i)

      with_data_sizes(sizes) do |data_source, num_objects|
        Benchmark.ips do |x|
          x.report("graphql-ruby lazy: #{num_objects} resolvers") do
            execute_graphql_ruby(GRAPHQL_GEM_LAZY_SCHEMA, document: DOCUMENT, root_value: data_source)
          end

          x.report("graphql-ruby dataloader: #{num_objects} resolvers") do
            execute_graphql_ruby(GRAPHQL_GEM_DATALOADER_SCHEMA, document: DOCUMENT, root_value: data_source)
          end

          x.report("graphql-ruby batch: #{num_objects} resolvers") do
            execute_graphql_ruby(GRAPHQL_GEM_BATCH_LOADER_SCHEMA, document: DOCUMENT, root_value: data_source)
          end

          x.report("graphql-cardinal: #{num_objects} lazy resolvers") do
            GraphQL::BreadthExec::Executor.new(
              SCHEMA,
              DOCUMENT,
              resolvers: BREADTH_DEFERRED_RESOLVERS,
              root_object: data_source,
              tracers: [CARDINAL_TRACER],
            ).result
          end

          x.compare!
        end
      end
    end

    def benchmark_introspection
      document = GraphQL.parse(GraphQL::Introspection.query)

      Benchmark.ips do |x|
        x.report("graphql-ruby: introspection") do
          execute_graphql_ruby(GRAPHQL_GEM_SCHEMA, document: document)
        end

        x.report("graphql-cardinal introspection") do
          GraphQL::BreadthExec::Executor.new(
            SCHEMA,
            document,
            resolvers: BREADTH_RESOLVERS,
            root_object: {},
            tracers: [CARDINAL_TRACER],
          ).result
        end

        x.compare!
      end
    end

    def benchmark_resolve_batch
      iterations = ENV.fetch("ITERATIONS", 5).to_i

      Benchmark.ips do |x|
        x.config(time: iterations, warmup: 1)

        x.report("graphql-ruby classic: #{RESOLVE_BATCH_OBJECT_COUNT} x 3 scalars") do
          execute_graphql_ruby(ClassicResolveBatchSchema, document: RESOLVE_BATCH_DOCUMENT, root_value: RESOLVE_BATCH_DATA)
        end

        if defined?(ResolveBatchSchema) && ResolveBatchSchema.respond_to?(:execute_next)
          x.report("graphql-ruby resolve_batch: #{RESOLVE_BATCH_OBJECT_COUNT} x 3 scalars") do
            execute_graphql_ruby_next(ResolveBatchSchema, document: RESOLVE_BATCH_DOCUMENT, root_value: RESOLVE_BATCH_DATA)
          end
        else
          warn "Skipping graphql-ruby resolve_batch: GraphQL::Execution::Next#execute_next is not available in graphql #{GraphQL::VERSION}."
        end

        x.report("graphql-breadth_exec: #{RESOLVE_BATCH_OBJECT_COUNT} x 3 scalars") do
          GraphQL::BreadthExec::Executor.new(
            RESOLVE_BATCH_BREADTH_SCHEMA,
            RESOLVE_BATCH_DOCUMENT,
            resolvers: RESOLVE_BATCH_RESOLVERS,
            root_object: RESOLVE_BATCH_DATA,
            tracers: [CARDINAL_TRACER],
          ).result
        end

        x.compare!
      end
    end

    def benchmark_lazy_scalars
      iterations = ENV.fetch("ITERATIONS", 5).to_i

      Benchmark.ips do |x|
        x.config(time: iterations, warmup: 1)

        x.report("graphql-breadth_exec lazy: #{RESOLVE_BATCH_OBJECT_COUNT} x 3 scalars") do
          GraphQL::BreadthExec::Executor.new(
            RESOLVE_BATCH_BREADTH_SCHEMA,
            RESOLVE_BATCH_DOCUMENT,
            resolvers: LAZY_SCALAR_BREADTH_RESOLVERS,
            root_object: RESOLVE_BATCH_DATA,
            tracers: [CARDINAL_TRACER],
          ).result
        end

        x.report("graphql-ruby graphql-batch: #{RESOLVE_BATCH_OBJECT_COUNT} x 3 scalars") do
          execute_graphql_ruby(LazyScalarBatchSchema, document: RESOLVE_BATCH_DOCUMENT, root_value: RESOLVE_BATCH_DATA)
        end

        x.report("graphql-ruby dataloader: #{RESOLVE_BATCH_OBJECT_COUNT} x 3 scalars") do
          execute_graphql_ruby(LazyScalarDataloaderSchema, document: RESOLVE_BATCH_DOCUMENT, root_value: RESOLVE_BATCH_DATA)
        end

        x.compare!
      end
    end

    def benchmark_lazy_field_batch
      iterations = ENV.fetch("ITERATIONS", 5).to_i

      Benchmark.ips do |x|
        x.config(time: iterations, warmup: 1)

        x.report("graphql-ruby graphql-batch: #{RESOLVE_BATCH_OBJECT_COUNT} x 1 lazy scalar") do
          execute_graphql_ruby(LazyScalarBatchSchema, document: LAZY_FIELD_BATCH_DOCUMENT, root_value: RESOLVE_BATCH_DATA)
        end

        if defined?(LazyFieldNextBatchSchema) && LazyFieldNextBatchSchema.respond_to?(:execute_next)
          x.report("graphql-ruby execute_next + graphql-batch: #{RESOLVE_BATCH_OBJECT_COUNT} x 1 lazy scalar") do
            execute_graphql_ruby_next(LazyFieldNextBatchSchema, document: LAZY_FIELD_BATCH_DOCUMENT, root_value: RESOLVE_BATCH_DATA)
          end
        else
          warn "Skipping graphql-ruby execute_next + graphql-batch: GraphQL::Execution::Next#execute_next is not available in graphql #{GraphQL::VERSION}."
        end

        if defined?(LazyFieldNextDataloaderSchema) && LazyFieldNextDataloaderSchema.respond_to?(:execute_next)
          x.report("graphql-ruby execute_next + dataloader: #{RESOLVE_BATCH_OBJECT_COUNT} x 1 lazy scalar") do
            execute_graphql_ruby_next(LazyFieldNextDataloaderSchema, document: LAZY_FIELD_BATCH_DOCUMENT, root_value: RESOLVE_BATCH_DATA)
          end
        else
          warn "Skipping graphql-ruby execute_next + dataloader: GraphQL::Execution::Next#execute_next is not available in graphql #{GraphQL::VERSION}."
        end

        x.report("graphql-ruby dataloader: #{RESOLVE_BATCH_OBJECT_COUNT} x 1 lazy scalar") do
          execute_graphql_ruby(LazyScalarDataloaderSchema, document: LAZY_FIELD_BATCH_DOCUMENT, root_value: RESOLVE_BATCH_DATA)
        end

        x.report("graphql-breadth_exec LazyLoader: #{RESOLVE_BATCH_OBJECT_COUNT} x 1 lazy scalar") do
          GraphQL::BreadthExec::Executor.new(
            RESOLVE_BATCH_BREADTH_SCHEMA,
            LAZY_FIELD_BATCH_DOCUMENT,
            resolvers: LAZY_SCALAR_BREADTH_RESOLVERS,
            root_object: RESOLVE_BATCH_DATA,
            tracers: [CARDINAL_TRACER],
          ).result
        end

        x.compare!
      end
    end

    def memory_profile
      default_data_sizes = "10, 1000"
      sizes = ENV.fetch("SIZES", default_data_sizes).split(",").map(&:to_i)

      with_data_sizes(sizes) do |data_source, num_objects|
        report = MemoryProfiler.report do
          execute_graphql_ruby(GRAPHQL_GEM_SCHEMA, document: DOCUMENT, root_value: data_source)
        end

        puts "\n\ngraphql-ruby memory profile: #{num_objects} resolvers"
        puts "=" * 50
        report.pretty_print
      end

      with_data_sizes(sizes) do |data_source, num_objects|
        report = MemoryProfiler.report do
          GraphQL::BreadthExec::Executor.new(
            SCHEMA,
            DOCUMENT,
            resolvers: BREADTH_RESOLVERS,
            root_object: data_source,
            tracers: [CARDINAL_TRACER],
          ).result
        end

        puts "\n\ngraphql-cardinal memory profile: #{num_objects} resolvers"
        puts "=" * 50
        report.pretty_print
      end
    end

    def with_data_sizes(sizes = [10])
      sizes.each do |size|
        products = (1..size).map do |i|
          {
            "id" => i.to_s,
            "title" => "Product #{i}",
            "variants" => {
              "nodes" => (1..5).map do |j|
                {
                  "id" => "#{i}-#{j}",
                  "title" => "Variant #{j}"
                }
              end
            }
          }
        end

        data = {
          "products" => {
            "nodes" => products
          }
        }

        num_objects = object_count(data)

        yield data, num_objects
      end
    end

    def object_count(obj)
      case obj
      when Hash
        obj.size + obj.values.sum { |value| object_count(value) }
      when Array
        obj.sum { |item| object_count(item) }
      else
        0
      end
    end
  end
end
