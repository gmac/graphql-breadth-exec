# frozen_string_literal: true

require "bundler/gem_helper"
Bundler::GemHelper.install_tasks

require "rake/testtask"

Rake::TestTask.new(:test) do |t, args|
  puts args
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

# Load rake tasks from lib/tasks
Dir.glob("lib/tasks/*.rake").each { |r| load r }

namespace :benchmark do
  def prepare_benchmark
    require_relative("./benchmark/run.rb")
  end

  desc "Benchmark execution"
  task :execution do
    prepare_benchmark
    GraphQLBenchmark.benchmark_execution
  end

  desc "Memory profile"
  task :memory do
    prepare_benchmark
    GraphQLBenchmark.memory_profile
  end
end

task default: :test
