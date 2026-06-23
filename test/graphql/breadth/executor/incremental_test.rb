# frozen_string_literal: true

require "test_helper"

class GraphQL::Breadth::Executor::IncrementalTest < Minitest::Test
  class BatchTrackingLoader < GraphQL::Breadth::LazyLoader
    class << self
      attr_accessor :perform_keys
    end

    self.perform_keys = []

    def map?
      true
    end

    def perform_map(keys, _ctx)
      self.class.perform_keys << keys.dup
      keys
    end
  end

  class LazyHashResolver < GraphQL::Breadth::FieldResolver
    def initialize(key)
      @key = key
    end

    def resolve(exec_field, _ctx)
      exec_field.lazy(loader_class: BatchTrackingLoader, keys: exec_field.objects.map { _1[@key] })
    end
  end

  class PagedProductNodesResolver < GraphQL::Breadth::FieldResolver
    attr_reader :calls

    def initialize(page_size: nil)
      @page_size = page_size
      @calls = []
    end

    def stream?
      true
    end

    def resolve(exec_field, _ctx)
      exec_field.map_objects { _1["nodes"] }
    end

    def resolve_list_stream(objects, _ctx, state:, object_states:, limit:, iteration:, field:)
      state[:calls] = @calls
      @calls << {
        limit:,
        iteration:,
        object_count: objects.length,
        arguments: field.arguments,
      }

      objects.map.with_index do |object, index|
        nodes = object.fetch("nodes")
        object_state = object_states[index]
        offset = object_state[:offset] || 0
        page_size = limit || @page_size || nodes.length
        items = nodes.slice(offset, page_size) || []
        object_state[:offset] = offset + items.length
        complete = object_state[:offset] >= nodes.length

        complete && items.empty? ? nil : GraphQL::Breadth::ListStreamChunk.new(items:, complete:)
      end
    end
  end

  class LazyPagedProductNodesResolver < GraphQL::Breadth::FieldResolver
    def stream?
      true
    end

    def resolve(exec_field, _ctx)
      exec_field.map_objects { _1["nodes"] }
    end

    def resolve_list_stream(objects, _ctx, state:, object_states:, limit:, iteration:, field:)
      field
        .lazy(loader_class: BatchTrackingLoader, keys: objects.map { [field.key, _1["nodes"]] })
        .then do |entries|
          entries.map do |(_field_key, nodes)|
            GraphQL::Breadth::ListStreamChunk.new(items: nodes, complete: true)
          end
        end
    end
  end

  class PagedVariantNodesResolver < GraphQL::Breadth::FieldResolver
    attr_reader :calls

    def initialize
      @calls = []
    end

    def stream?
      true
    end

    def resolve(exec_field, _ctx)
      exec_field.map_objects { _1["nodes"] }
    end

    def resolve_list_stream(objects, _ctx, state:, object_states:, limit:, iteration:, field:)
      state[:calls] = @calls
      @calls << {
        limit:,
        iteration:,
        objects: objects.map { _1["name"] },
        arguments: field.arguments,
      }

      objects.map.with_index do |object, index|
        nodes = object.fetch("nodes")
        object_state = object_states[index]
        offset = object_state[:offset] || 0
        page_size = limit || 1
        items = nodes.slice(offset, page_size) || []
        object_state[:offset] = offset + items.length

        if iteration.zero?
          GraphQL::Breadth::ListStreamChunk.new(items:, complete: false)
        else
          complete = object_state[:offset] >= nodes.length
          complete && items.empty? ? nil : GraphQL::Breadth::ListStreamChunk.new(items:, complete:)
        end
      end
    end
  end

  SOURCE = {
    "products" => {
      "nodes" => [{
        "id" => "gid://shopify/Product/1",
        "title" => "Banana",
        "must" => "yes",
        "variants" => {
          "nodes" => [{
            "id" => "gid://shopify/Variant/1",
            "title" => "Small Banana",
          }],
        },
      }, {
        "id" => "gid://shopify/Product/2",
        "title" => "Apple",
        "must" => "yes",
        "variants" => {
          "nodes" => [{
            "id" => "gid://shopify/Variant/2",
            "title" => "Small Apple",
          }],
        },
      }],
    },
  }.freeze

  PAGED_VARIANTS_SOURCE = {
    "products" => {
      "nodes" => [{
        "id" => "gid://shopify/Product/1",
        "title" => "Banana",
        "variants" => {
          "name" => "Banana variants",
          "nodes" => [{
            "id" => "gid://shopify/Variant/1",
            "title" => "Small Banana",
          }],
        },
      }, {
        "id" => "gid://shopify/Product/2",
        "title" => "Apple",
        "variants" => {
          "name" => "Apple variants",
          "nodes" => [{
            "id" => "gid://shopify/Variant/2",
            "title" => "Small Apple",
          }, {
            "id" => "gid://shopify/Variant/3",
            "title" => "Medium Apple",
          }, {
            "id" => "gid://shopify/Variant/4",
            "title" => "Large Apple",
          }],
        },
      }],
    },
  }.freeze

  def test_incremental_result_returns_normal_result_without_defer
    result = build_executor(%|{
      products(first: 2) {
        nodes {
          id
          title
        }
      }
    }|).incremental_result

    expected = {
      "data" => {
        "products" => {
          "nodes" => [
            { "id" => "gid://shopify/Product/1", "title" => "Banana" },
            { "id" => "gid://shopify/Product/2", "title" => "Apple" },
          ],
        },
      },
    }

    assert_instance_of GraphQL::Breadth::Incremental::Result, result
    refute result.incremental?
    assert_equal expected, result.initial_result
    assert_equal [], result.subsequent_results.to_a
    assert_equal expected, result.to_h
  end

  def test_incremental_result_raises_after_result
    executor = build_executor(%|{
      products(first: 2) {
        nodes { id }
      }
    }|)

    executor.result
    error = assert_raises(GraphQL::Breadth::ImplementationError) do
      executor.incremental_result
    end

    assert_equal "Cannot call incremental_result after result", error.message
  end

  def test_result_raises_after_incremental_result
    executor = build_executor(%|{
      products(first: 2) {
        nodes { id }
      }
    }|)

    executor.incremental_result
    error = assert_raises(GraphQL::Breadth::ImplementationError) do
      executor.result
    end

    assert_equal "Cannot call result after incremental_result", error.message
  end

  def test_incremental_result_returns_same_result_on_repeat_call
    executor = build_executor(%|{
      products(first: 2) {
        nodes { id }
      }
    }|)

    result = executor.incremental_result
    assert_same result, executor.incremental_result
  end

  def test_incremental_result_does_not_defer_when_if_is_false
    result = build_executor(%|{
      products(first: 1) {
        nodes {
          id
          ... @defer(if: false) { title }
        }
      }
    }|).incremental_result

    expected = {
      "data" => {
        "products" => {
          "nodes" => [
            { "id" => "gid://shopify/Product/1", "title" => "Banana" },
            { "id" => "gid://shopify/Product/2", "title" => "Apple" },
          ],
        },
      },
    }

    assert_instance_of GraphQL::Breadth::Incremental::Result, result
    refute result.incremental?
    assert_equal expected, result.initial_result
    assert_equal [], result.subsequent_results.to_a
    assert_equal(
      expected,
      result.to_h,
    )
  end

  def test_incremental_result_defers_when_if_is_null
    result = build_executor(%|query($shouldDefer: Boolean) {
      products(first: 1) {
        nodes {
          id
          ... @defer(if: $shouldDefer) { title }
        }
      }
    }|, source: one_product_source).incremental_result

    assert_equal(
      {
        "data" => {
          "products" => {
            "nodes" => [{ "id" => "gid://shopify/Product/1" }],
          },
        },
        "pending" => [{ "id" => "0", "path" => ["products", "nodes", 0] }],
        "hasNext" => true,
      },
      result.initial_result,
    )
    assert_equal(
      [{
        "incremental" => [{ "data" => { "title" => "Banana" }, "id" => "0" }],
        "completed" => [{ "id" => "0" }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_defers_fragment_for_each_list_object
    result = build_executor(%|{
      products(first: 2) {
        nodes {
          id
          ... @defer { title }
        }
      }
    }|).incremental_result

    assert_instance_of GraphQL::Breadth::Incremental::Result, result
    assert_equal(
      {
        "data" => {
          "products" => {
            "nodes" => [
              { "id" => "gid://shopify/Product/1" },
              { "id" => "gid://shopify/Product/2" },
            ],
          },
        },
        "pending" => [
          { "id" => "0", "path" => ["products", "nodes", 0] },
          { "id" => "1", "path" => ["products", "nodes", 1] },
        ],
        "hasNext" => true,
      },
      result.initial_result,
    )

    assert_equal(
      [{
        "incremental" => [
          { "data" => { "title" => "Banana" }, "id" => "0" },
          { "data" => { "title" => "Apple" }, "id" => "1" },
        ],
        "completed" => [
          { "id" => "0" },
          { "id" => "1" },
        ],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_includes_defer_label
    result = build_executor(%|{
      products(first: 1) {
        nodes {
          id
          ... @defer(label: "ProductTitle") { title }
        }
      }
    }|, source: one_product_source).incremental_result

    assert_equal(
      [{ "id" => "0", "path" => ["products", "nodes", 0], "label" => "ProductTitle" }],
      result.initial_result.fetch("pending"),
    )
  end

  def test_incremental_result_treats_null_label_as_no_label
    result = build_executor(%|{
      products(first: 1) {
        nodes {
          id
          ... @defer(label: null) { title }
        }
      }
    }|, source: one_product_source).incremental_result

    assert_equal(
      [{ "id" => "0", "path" => ["products", "nodes", 0] }],
      result.initial_result.fetch("pending"),
    )
  end

  def test_incremental_result_deduplicates_fragment_also_selected_without_defer
    [
      %|query ProductTitleQuery {
        products(first: 1) {
          nodes {
            ...Title @defer(label: "DeferredTitle")
            ...Title
          }
        }
      }

      fragment Title on Product {
        title
      }|,
      %|query ProductTitleQuery {
        products(first: 1) {
          nodes {
            ...Title
            ...Title @defer(label: "DeferredTitle")
          }
        }
      }

      fragment Title on Product {
        title
      }|,
    ].each do |document|
      result = build_executor(document, source: one_product_source).incremental_result

      expected = {
        "data" => {
          "products" => {
            "nodes" => [{ "title" => "Banana" }],
          },
        },
      }

      refute result.incremental?
      assert_equal expected, result.initial_result
      assert_equal [], result.subsequent_results.to_a
    end
  end

  def test_incremental_result_defers_inline_fragment
    result = build_executor(%|{
      products(first: 1) {
        nodes {
          id
          ... on Product @defer(label: "InlineTitle") {
            title
          }
        }
      }
    }|, source: one_product_source).incremental_result

    assert_equal(
      {
        "data" => {
          "products" => {
            "nodes" => [{ "id" => "gid://shopify/Product/1" }],
          },
        },
        "pending" => [{ "id" => "0", "path" => ["products", "nodes", 0], "label" => "InlineTitle" }],
        "hasNext" => true,
      },
      result.initial_result,
    )
    assert_equal(
      [{
        "incremental" => [{ "data" => { "title" => "Banana" }, "id" => "0" }],
        "completed" => [{ "id" => "0" }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_does_not_emit_empty_defer_fragments
    result = build_executor(%|{
      products(first: 1) {
        nodes {
          ... @defer {
            title @skip(if: true)
          }
        }
      }
    }|, source: one_product_source).incremental_result

    expected = {
      "data" => {
        "products" => {
          "nodes" => [{}],
        },
      },
    }

    refute result.incremental?
    assert_equal expected, result.initial_result
    assert_equal [], result.subsequent_results.to_a
  end

  def test_incremental_result_emits_children_of_empty_defer_fragments
    result = build_executor(%|{
      products(first: 1) {
        nodes {
          ... @defer {
            ... @defer {
              title
            }
          }
        }
      }
    }|, source: one_product_source).incremental_result

    assert_equal(
      {
        "data" => {
          "products" => {
            "nodes" => [{}],
          },
        },
        "pending" => [{ "id" => "0", "path" => ["products", "nodes", 0] }],
        "hasNext" => true,
      },
      result.initial_result,
    )
    assert_equal(
      [{
        "incremental" => [{ "data" => { "title" => "Banana" }, "id" => "0" }],
        "completed" => [{ "id" => "0" }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_deduplicates_nested_defers_on_the_same_object
    result = build_executor(%|query ProductTitleQuery {
      products(first: 1) {
        nodes {
          ... @defer {
            ...ProductTitle
            ... @defer {
              ...ProductTitle
              ... @defer {
                ...ProductTitle
              }
            }
          }
        }
      }
    }

    fragment ProductTitle on Product {
      id
      title
    }|, source: one_product_source).incremental_result

    assert_equal(
      {
        "data" => {
          "products" => {
            "nodes" => [{}],
          },
        },
        "pending" => [{ "id" => "0", "path" => ["products", "nodes", 0] }],
        "hasNext" => true,
      },
      result.initial_result,
    )
    assert_equal(
      [{
        "incremental" => [{
          "data" => {
            "id" => "gid://shopify/Product/1",
            "title" => "Banana",
          },
          "id" => "0",
        }],
        "completed" => [{ "id" => "0" }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_defers_top_level_fragment
    result = build_executor(%|{
      ... @defer(label: "Top") {
        products(first: 1) {
          nodes { title }
        }
      }
    }|).incremental_result

    assert_equal(
      {
        "data" => {},
        "pending" => [{ "id" => "0", "path" => [], "label" => "Top" }],
        "hasNext" => true,
      },
      result.initial_result,
    )
    assert_equal(
      [{
        "incremental" => [{
          "data" => {
            "products" => {
              "nodes" => [
                { "title" => "Banana" },
                { "title" => "Apple" },
              ],
            },
          },
          "id" => "0",
        }],
        "completed" => [{ "id" => "0" }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_formats_errors_in_top_level_deferred_fragment
    source = Marshal.load(Marshal.dump(one_product_source))
    source["products"]["nodes"][0]["title"] = GraphQL::ExecutionError.new("No title")

    result = build_executor(%|{
      ... @defer(label: "Top") {
        products(first: 1) {
          nodes { title }
        }
      }
    }|, source: source).incremental_result

    assert_equal(
      {
        "data" => {},
        "pending" => [{ "id" => "0", "path" => [], "label" => "Top" }],
        "hasNext" => true,
      },
      result.initial_result,
    )
    assert_equal(
      [{
        "incremental" => [{
          "data" => {
            "products" => {
              "nodes" => [{ "title" => nil }],
            },
          },
          "id" => "0",
          "errors" => [{
            "message" => "No title",
            "locations" => [{ "line" => 4, "column" => 19 }],
            "path" => ["products", "nodes", 0, "title"],
          }],
        }],
        "completed" => [{ "id" => "0" }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_separately_emits_fragments_with_different_labels
    result = build_executor(%|{
      products(first: 1) {
        nodes {
          ... @defer(label: "DeferredId") { id }
          ... @defer(label: "DeferredTitle") { title }
        }
      }
    }|, source: one_product_source).incremental_result

    assert_equal(
      {
        "data" => {
          "products" => {
            "nodes" => [{}],
          },
        },
        "pending" => [
          { "id" => "0", "path" => ["products", "nodes", 0], "label" => "DeferredId" },
          { "id" => "1", "path" => ["products", "nodes", 0], "label" => "DeferredTitle" },
        ],
        "hasNext" => true,
      },
      result.initial_result,
    )
    assert_equal(
      [{
        "incremental" => [
          { "data" => { "id" => "gid://shopify/Product/1" }, "id" => "0" },
          { "data" => { "title" => "Banana" }, "id" => "1" },
        ],
        "completed" => [{ "id" => "0" }, { "id" => "1" }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_uses_sub_path_for_nested_payloads
    result = build_executor(%|{
      ... @defer(label: "DeferredId") {
        products(first: 1) {
          nodes { id }
        }
      }
      ... @defer(label: "DeferredTitle") {
        products(first: 1) {
          nodes { title }
        }
      }
    }|, source: one_product_source).incremental_result

    assert_equal(
      {
        "data" => {},
        "pending" => [
          { "id" => "0", "path" => [], "label" => "DeferredId" },
          { "id" => "1", "path" => [], "label" => "DeferredTitle" },
        ],
        "hasNext" => true,
      },
      result.initial_result,
    )
    assert_equal(
      [{
        "incremental" => [
          {
            "data" => {
              "products" => {
                "nodes" => [{}],
              },
            },
            "id" => "0",
          },
          {
            "data" => { "id" => "gid://shopify/Product/1" },
            "id" => "0",
            "subPath" => ["products", "nodes", 0],
          },
          {
            "data" => { "title" => "Banana" },
            "id" => "1",
            "subPath" => ["products", "nodes", 0],
          },
        ],
        "completed" => [{ "id" => "0" }, { "id" => "1" }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_formats_nullable_errors_in_deferred_payload
    source = Marshal.load(Marshal.dump(SOURCE))
    source["products"]["nodes"][0]["title"] = GraphQL::ExecutionError.new("Oops!")

    result = build_executor(%|{
      products(first: 1) {
        nodes {
          id
          ... @defer { title }
        }
      }
    }|, source: source).incremental_result

    assert_equal(
      [{
        "incremental" => [
          {
            "data" => { "title" => nil },
            "id" => "0",
            "errors" => [{
              "message" => "Oops!",
              "locations" => [{ "line" => 5, "column" => 24 }],
              "path" => ["products", "nodes", 0, "title"],
            }],
          },
          { "data" => { "title" => "Apple" }, "id" => "1" },
        ],
        "completed" => [
          { "id" => "0" },
          { "id" => "1" },
        ],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_supports_nested_defer
    result = build_executor(%|{
      products(first: 1) {
        nodes {
          id
          ... @defer(label: "Outer") {
            title
            variants(first: 1) {
              nodes {
                id
                ... @defer(label: "Inner") { title }
              }
            }
          }
        }
      }
    }|, source: one_product_source).incremental_result

    assert_equal(
      {
        "data" => {
          "products" => {
            "nodes" => [{ "id" => "gid://shopify/Product/1" }],
          },
        },
        "pending" => [{ "id" => "0", "path" => ["products", "nodes", 0], "label" => "Outer" }],
        "hasNext" => true,
      },
      result.initial_result,
    )
    assert_equal(
      [{
        "pending" => [{
          "id" => "1",
          "path" => ["products", "nodes", 0, "variants", "nodes", 0],
          "label" => "Inner",
        }],
        "incremental" => [
          {
            "data" => {
              "title" => "Banana",
              "variants" => {
                "nodes" => [{ "id" => "gid://shopify/Variant/1" }],
              },
            },
            "id" => "0",
          },
          { "data" => { "title" => "Small Banana" }, "id" => "1" },
        ],
        "completed" => [
          { "id" => "0" },
          { "id" => "1" },
        ],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_cancels_nested_defer_when_parent_deferred_fragment_fails
    source = Marshal.load(Marshal.dump(SOURCE))
    source["products"]["nodes"] = [source["products"]["nodes"].first]
    source["products"]["nodes"][0]["must"] = nil

    result = build_executor(%|{
      products(first: 1) {
        nodes {
          id
          ... @defer(label: "Outer") {
            must
            variants(first: 1) {
              nodes {
                id
                ... @defer(label: "Inner") { title }
              }
            }
          }
        }
      }
    }|, source: source).incremental_result

    assert_equal(
      {
        "data" => {
          "products" => {
            "nodes" => [{ "id" => "gid://shopify/Product/1" }],
          },
        },
        "pending" => [{ "id" => "0", "path" => ["products", "nodes", 0], "label" => "Outer" }],
        "hasNext" => true,
      },
      result.initial_result,
    )
    assert_equal(
      [{
        "completed" => [{
          "id" => "0",
          "errors" => [{
            "message" => "Cannot return null for non-nullable field Product.must",
            "locations" => [{ "line" => 6, "column" => 13 }],
            "path" => ["products", "nodes", 0, "must"],
            "extensions" => { "code" => "INVALID_NULL" },
          }],
        }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_completes_deferred_group_with_non_null_errors
    source = Marshal.load(Marshal.dump(SOURCE))
    source["products"]["nodes"][0]["must"] = nil
    source["products"]["nodes"] = [source["products"]["nodes"][0]]

    result = build_executor(%|{
      products(first: 1) {
        nodes {
          id
          ... @defer { must }
        }
      }
    }|, source: source).incremental_result

    assert_equal(
      [{
        "completed" => [{
          "id" => "0",
          "errors" => [{
            "message" => "Cannot return null for non-nullable field Product.must",
            "locations" => [{ "line" => 5, "column" => 24 }],
            "path" => ["products", "nodes", 0, "must"],
            "extensions" => { "code" => "INVALID_NULL" },
          }],
        }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_cancels_deferred_payload_for_null_bubbled_parent
    source = Marshal.load(Marshal.dump(SOURCE))
    source["products"]["nodes"] = [source["products"]["nodes"].first]
    source["products"]["nodes"][0]["must"] = nil

    result = build_executor(%|{
      products(first: 1) {
        nodes {
          must
          ... @defer { title }
        }
      }
    }|, source: source).incremental_result

    assert_equal(
      { "products" => nil },
      result.initial_result.fetch("data"),
    )
    refute result.initial_result.key?("pending")
    refute result.initial_result.key?("hasNext")
    assert_equal(
      [{
        "message" => "Cannot return null for non-nullable field Product.must",
        "locations" => [{ "line" => 4, "column" => 11 }],
        "path" => ["products", "nodes", 0, "must"],
        "extensions" => { "code" => "INVALID_NULL" },
      }],
      result.initial_result.fetch("errors"),
    )
    assert_equal [], result.subsequent_results.to_a
  end

  def test_incremental_result_filters_deferred_payload_for_null_bubbled_list_element
    # `nodes: [Node]!` has NULLABLE elements. Element 0's non-null `must` returns nil, so the
    # element null-bubbles to null in the initial result while the list and its siblings survive
    # (no scope abort). A deferred fragment is attached to that now-dead element: it must NOT be
    # announced as pending or delivered as incremental — there is no live object to patch into.
    source = {
      "nodes" => [
        { "__typename__" => "Product", "id" => "1", "must" => nil, "title" => "Banana" },
        { "__typename__" => "Product", "id" => "2", "must" => "yes", "title" => "Apple" },
      ],
    }

    result = build_executor(%|{
      nodes(ids: ["1", "2"]) {
        ... on Product {
          id
          must
          ... @defer { title }
        }
      }
    }|, source: source).incremental_result

    assert_instance_of GraphQL::Breadth::Incremental::Result, result

    initial = result.initial_result
    assert_equal(
      { "nodes" => [nil, { "id" => "2", "must" => "yes" }] },
      initial.fetch("data"),
    )
    # only the surviving element (index 1) is announced; the null-bubbled element 0 is filtered out.
    assert_equal(
      [{ "id" => "0", "path" => ["nodes", 1] }],
      initial.fetch("pending"),
    )
    assert_equal(true, initial.fetch("hasNext"))
    assert_equal(["nodes", 0, "must"], initial.fetch("errors").first.fetch("path"))

    # the dead element delivers nothing; the surviving element delivers and completes normally.
    assert_equal(
      [{
        "incremental" => [{ "data" => { "title" => "Apple" }, "id" => "0" }],
        "completed" => [{ "id" => "0" }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_ready_deferred_executions_batch_lazy_work
    source = Marshal.load(Marshal.dump(SOURCE))
    source["products"]["nodes"][0]["maybe"] = "Yellow"
    source["products"]["nodes"][1]["maybe"] = "Red"

    resolvers = BREADTH_RESOLVERS.merge(
      "Product" => BREADTH_RESOLVERS.fetch("Product").merge(
        "title" => LazyHashResolver.new("title"),
        "maybe" => LazyHashResolver.new("maybe"),
      ),
    )

    BatchTrackingLoader.perform_keys = []

    result = build_executor(%|{
      products(first: 2) {
        nodes {
          id
          ... @defer(label: "Title") { title }
          ... @defer(label: "Maybe") { maybe }
        }
      }
    }|, source:, resolvers:).incremental_result

    result.subsequent_results.to_a

    assert_equal(
      [["Banana", "Apple", "Yellow", "Red"]],
      BatchTrackingLoader.perform_keys,
    )
  end

  def test_incremental_result_streams_list_field
    resolver = PagedProductNodesResolver.new
    result = build_executor(%|{
      products(first: 2) {
        nodes @stream(initialCount: 1) {
          id
          title
        }
      }
    }|, resolvers: stream_product_nodes_resolvers(resolver)).incremental_result

    assert_equal(
      {
        "data" => {
          "products" => {
            "nodes" => [{ "id" => "gid://shopify/Product/1", "title" => "Banana" }],
          },
        },
        "pending" => [{ "id" => "0", "path" => ["products", "nodes"] }],
        "hasNext" => true,
      },
      result.initial_result,
    )
    assert_equal(
      [{
        "incremental" => [{
          "items" => [{ "id" => "gid://shopify/Product/2", "title" => "Apple" }],
          "id" => "0",
        }],
        "completed" => [{ "id" => "0" }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_streams_with_default_initial_count
    resolver = PagedProductNodesResolver.new
    result = build_executor(%|{
      products(first: 2) {
        nodes @stream {
          id
        }
      }
    }|, resolvers: stream_product_nodes_resolvers(resolver)).incremental_result

    assert_equal(
      {
        "data" => {
          "products" => {
            "nodes" => [],
          },
        },
        "pending" => [{ "id" => "0", "path" => ["products", "nodes"] }],
        "hasNext" => true,
      },
      result.initial_result,
    )
    assert_equal(
      [{
        "incremental" => [{
          "items" => [
            { "id" => "gid://shopify/Product/1" },
            { "id" => "gid://shopify/Product/2" },
          ],
          "id" => "0",
        }],
        "completed" => [{ "id" => "0" }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
  end

  def test_incremental_result_batches_opt_in_list_streams_and_drops_completed_objects
    resolver = PagedVariantNodesResolver.new
    resolvers = BREADTH_RESOLVERS.merge(
      "VariantConnection" => BREADTH_RESOLVERS.fetch("VariantConnection").merge(
        "nodes" => resolver,
      ),
    )

    result = build_executor(%|{
      products(first: 2) {
        nodes {
          id
          variants(first: 3) {
            nodes @stream(initialCount: 1) {
              id
            }
          }
        }
      }
    }|, source: PAGED_VARIANTS_SOURCE, resolvers:).incremental_result

    assert_equal(
      {
        "data" => {
          "products" => {
            "nodes" => [{
              "id" => "gid://shopify/Product/1",
              "variants" => {
                "nodes" => [{ "id" => "gid://shopify/Variant/1" }],
              },
            }, {
              "id" => "gid://shopify/Product/2",
              "variants" => {
                "nodes" => [{ "id" => "gid://shopify/Variant/2" }],
              },
            }],
          },
        },
        "pending" => [
          { "id" => "0", "path" => ["products", "nodes", 0, "variants", "nodes"] },
          { "id" => "1", "path" => ["products", "nodes", 1, "variants", "nodes"] },
        ],
        "hasNext" => true,
      },
      result.initial_result,
    )
    assert_equal(
      [{
        "incremental" => [{
          "items" => [{ "id" => "gid://shopify/Variant/3" }],
          "id" => "1",
        }],
        "completed" => [{ "id" => "0" }],
        "hasNext" => true,
      }, {
        "incremental" => [{
          "items" => [{ "id" => "gid://shopify/Variant/4" }],
          "id" => "1",
        }],
        "completed" => [{ "id" => "1" }],
        "hasNext" => false,
      }],
      result.subsequent_results.to_a,
    )
    assert_equal(
      [{
        limit: 1,
        iteration: 0,
        objects: ["Banana variants", "Apple variants"],
        arguments: {},
      }, {
        limit: nil,
        iteration: 1,
        objects: ["Banana variants", "Apple variants"],
        arguments: {},
      }, {
        limit: nil,
        iteration: 2,
        objects: ["Apple variants"],
        arguments: {},
      }],
      resolver.calls,
    )
  end

  def test_incremental_result_includes_stream_label
    resolver = PagedProductNodesResolver.new
    result = build_executor(%|{
      products(first: 2) {
        nodes @stream(initialCount: 1, label: "ProductNodes") {
          id
        }
      }
    }|, resolvers: stream_product_nodes_resolvers(resolver)).incremental_result

    assert_equal(
      [{ "id" => "0", "path" => ["products", "nodes"], "label" => "ProductNodes" }],
      result.initial_result.fetch("pending"),
    )
  end

  def test_incremental_result_does_not_stream_when_if_is_false
    result = build_executor(%|{
      products(first: 2) {
        nodes @stream(initialCount: 0, if: false) {
          id
        }
      }
    }|).incremental_result

    expected = {
      "data" => {
        "products" => {
          "nodes" => [
            { "id" => "gid://shopify/Product/1" },
            { "id" => "gid://shopify/Product/2" },
          ],
        },
      },
    }

    refute result.incremental?
    assert_equal expected, result.initial_result
    assert_equal [], result.subsequent_results.to_a
  end

  def test_ready_stream_executions_batch_lazy_work
    resolvers = stream_product_nodes_resolvers.merge(
      "Product" => BREADTH_RESOLVERS.fetch("Product").merge(
        "title" => LazyHashResolver.new("title"),
      ),
    )

    BatchTrackingLoader.perform_keys = []

    result = build_executor(%|{
      products(first: 2) {
        nodes @stream {
          title
        }
      }
    }|, resolvers:).incremental_result

    result.subsequent_results.to_a

    assert_equal(
      [["Banana", "Apple"]],
      BatchTrackingLoader.perform_keys,
    )
  end

  def test_ready_list_stream_fields_batch_lazy_resolver_work_across_streams
    resolver = LazyPagedProductNodesResolver.new
    BatchTrackingLoader.perform_keys = []

    result = build_executor(%|{
      products(first: 2) {
        first: nodes @stream {
          id
        }
        second: nodes @stream {
          id
        }
      }
    }|, resolvers: stream_product_nodes_resolvers(resolver)).incremental_result

    result.subsequent_results.to_a

    nodes = SOURCE.fetch("products").fetch("nodes")
    assert_equal(
      [[["first", nodes], ["second", nodes]]],
      BatchTrackingLoader.perform_keys,
    )
  end

  private

  def stream_product_nodes_resolvers(resolver = PagedProductNodesResolver.new)
    BREADTH_RESOLVERS.merge(
      "ProductConnection" => BREADTH_RESOLVERS.fetch("ProductConnection").merge(
        "nodes" => resolver,
      ),
    )
  end

  def build_executor(document, source: SOURCE, resolvers: BREADTH_RESOLVERS)
    GraphQL::Breadth::Executor.new(
      SCHEMA,
      GraphQL.parse(document),
      resolvers: resolvers,
      root_object: source,
    )
  end

  def one_product_source
    {
      "products" => {
        "nodes" => [SOURCE.fetch("products").fetch("nodes").first],
      },
    }
  end
end
