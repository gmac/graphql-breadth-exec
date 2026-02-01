# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::ConditionalsTest < Minitest::Test
  SOURCE = {
    "products" => {
      "nodes" => [
        { "id" => "Product/1", "title" => "Product 1" },
        { "id" => "Product/2", "title" => "Product 2" },
      ],
    },
  }.freeze

  SKIPPED_SOURCE = {
    "products" => {
      "nodes" => [
        { "id" => "Product/1" },
        { "id" => "Product/2" },
      ],
    },
  }.freeze

  def test_follows_skip_directive_omissions
    document = %|{
      products(first: 3) {
        nodes {
          id
          title @skip(if: true)
        }
      }
    }|

    assert_equal SKIPPED_SOURCE, breadth_exec(document, SOURCE).dig("data")
  end

  def test_follows_skip_directive_inclusions
    document = %|{
      products(first: 3) {
        nodes {
          id
          title @skip(if: false)
        }
      }
    }|

    assert_equal SOURCE, breadth_exec(document, SOURCE).dig("data")
  end

  def test_follows_skip_directives_with_string_variable
    document = %|query($skip: Boolean!) {
      products(first: 3) {
        nodes {
          id
          title @skip(if: $skip)
        }
      }
    }|

    assert_equal SKIPPED_SOURCE, breadth_exec(document, SOURCE, variables: { "skip" => true }).dig("data")
  end

  def test_follows_skip_directives_with_symbol_variable
    document = %|query($skip: Boolean!) {
      products(first: 3) {
        nodes {
          id
          title @skip(if: $skip)
        }
      }
    }|

    assert_equal SKIPPED_SOURCE, breadth_exec(document, SOURCE, variables: { skip: true }).dig("data")
  end

  def test_follows_include_directive_omissions
    document = %|{
      products(first: 3) {
        nodes {
          id
          title @include(if: false)
        }
      }
    }|

    assert_equal SKIPPED_SOURCE, breadth_exec(document, SOURCE).dig("data")
  end

  def test_follows_include_directive_inclusions
    document = %|{
      products(first: 3) {
        nodes {
          id
          title @include(if: true)
        }
      }
    }|

    assert_equal SOURCE, breadth_exec(document, SOURCE).dig("data")
  end

  def test_follows_include_directives_with_string_variable
    document = %|query($include: Boolean!) {
      products(first: 3) {
        nodes {
          id
          title @include(if: $include)
        }
      }
    }|

    assert_equal SKIPPED_SOURCE, breadth_exec(document, SOURCE, variables: { "include" => false }).dig("data")
  end

  def test_follows_include_directives_with_symbol_variable
    document = %|query($include: Boolean!) {
      products(first: 3) {
        nodes {
          id
          title @include(if: $include)
        }
      }
    }|

    assert_equal SKIPPED_SOURCE, breadth_exec(document, SOURCE, variables: { include: false }).dig("data")
  end
end
