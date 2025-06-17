# frozen_string_literal: true

require "test_helper"

class GraphQL::Cardinal::DepthExecutorTest < Minitest::Test
  def test_runs
    assert_equal BASIC_SOURCE, depth_exec(BASIC_DOCUMENT, BASIC_SOURCE).dig("data")
  end
end
