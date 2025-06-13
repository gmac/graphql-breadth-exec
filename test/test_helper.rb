# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'warning'
Gem.path.each do |path|
  # ignore warnings from auto-generated GraphQL lib code.
  Warning.ignore(/.*mismatched indentations.*/)
  Warning.ignore(/.*lib\/graphql\/language\/nodes.rb:.*/)
end

require 'bundler/setup'
Bundler.require(:default, :test)

require 'minitest/pride'
require 'minitest/autorun'
require 'minitest/stub_const'
require 'graphql/cardinal'
require_relative './fixtures'
