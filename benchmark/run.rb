# frozen_string_literal: true
#
require "debug"
require "graphql"
require "graphql/batch"
require "graphql/cardinal"

require "benchmark/ips"
require "memory_profiler"
require_relative '../test/fixtures'

class GraphQLBenchmark
  DOCUMENT = GraphQL.parse(BASIC_DOCUMENT)
  CARDINAL_SCHEMA = SCHEMA
  CARDINAL_TRACER = GraphQL::Cardinal::Tracer.new

  class Schema < GraphQL::Schema
    lazy_resolve(Proc, :call)
  end

  class DataloaderSchema < GraphQL::Schema
    use GraphQL::Dataloader
  end

  class BatchLoaderSchema < GraphQL::Schema
    use GraphQL::Batch
  end

  GRAPHQL_GEM_SCHEMA = Schema.from_definition(SDL, default_resolve: GEM_RESOLVERS)
  GRAPHQL_GEM_LAZY_SCHEMA = Schema.from_definition(SDL, default_resolve: GEM_LAZY_RESOLVERS)
  GRAPHQL_GEM_DATALOADER_SCHEMA = DataloaderSchema.from_definition(SDL, default_resolve: GEM_DATALOADER_RESOLVERS)
  GRAPHQL_GEM_DATALOADER_SCHEMA.use(GraphQL::Dataloader)

  GRAPHQL_GEM_BATCH_LOADER_SCHEMA = BatchLoaderSchema.from_definition(SDL, default_resolve: GEM_BATCH_LOADER_RESOLVERS)
  GRAPHQL_GEM_BATCH_LOADER_SCHEMA.use(GraphQL::Batch)

  class << self
    def benchmark_execution
      default_data_sizes = "10, 100, 1000, 10000"
      sizes = ENV.fetch("SIZES", default_data_sizes).split(",").map(&:to_i)

      with_data_sizes(sizes) do |data_source, num_objects|
        Benchmark.ips do |x|
          x.report("graphql-ruby: #{num_objects} resolvers") do
            GRAPHQL_GEM_SCHEMA.execute(document: DOCUMENT, root_value: data_source)
          end

          x.report("graphql-cardinal #{num_objects} resolvers") do
            GraphQL::Cardinal::Executor.new(
              SCHEMA,
              BREADTH_RESOLVERS,
              DOCUMENT,
              data_source,
              tracers: [CARDINAL_TRACER],
            ).perform
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
          # x.report("graphql-ruby lazy: #{num_objects} resolvers") do
          #   GRAPHQL_GEM_LAZY_SCHEMA.execute(document: DOCUMENT, root_value: data_source)
          # end

          # x.report("graphql-ruby dataloader: #{num_objects} resolvers") do
          #   GRAPHQL_GEM_DATALOADER_SCHEMA.execute(document: DOCUMENT, root_value: data_source)
          # end

          # x.report("graphql-ruby batch: #{num_objects} resolvers") do
          #   GRAPHQL_GEM_BATCH_LOADER_SCHEMA.execute(document: DOCUMENT, root_value: data_source)
          # end

          x.report("graphql-cardinal #{num_objects} resolvers") do
            GraphQL::Cardinal::Executor.new(
              SCHEMA,
              BREADTH_RESOLVERS,
              DOCUMENT,
              data_source,
              tracers: [CARDINAL_TRACER],
            ).perform
          end

          x.report("graphql-cardinal: #{num_objects} lazy resolvers") do
            GraphQL::Cardinal::Executor.new(
              SCHEMA,
              BREADTH_DEFERRED_RESOLVERS,
              DOCUMENT,
              data_source,
              tracers: [CARDINAL_TRACER],
            ).perform
          end

          x.compare!
        end
      end
    end

    def memory_profile
      default_data_sizes = "10, 1000"
      sizes = ENV.fetch("SIZES", default_data_sizes).split(",").map(&:to_i)

      with_data_sizes(sizes) do |data_source, num_objects|
        report = MemoryProfiler.report do
          GRAPHQL_GEM_SCHEMA.execute(document: DOCUMENT, root_value: data_source)
        end

        puts "\n\ngraphql-ruby memory profile: #{num_objects} resolvers"
        puts "=" * 50
        report.pretty_print
      end

      with_data_sizes(sizes) do |data_source, num_objects|
        report = MemoryProfiler.report do
          GraphQL::Cardinal::Executor.new(
            SCHEMA,
            BREADTH_RESOLVERS,
            DOCUMENT,
            data_source,
            tracers: [CARDINAL_TRACER],
          ).perform
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
