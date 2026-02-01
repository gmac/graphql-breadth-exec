SDL = <<~SCHEMA
  interface Node {
    id: ID!
  }

  interface HasMetafields {
    metafield(key: String!): Metafield
  }

  type Metafield {
    key: String!
    value: String!
  }

  type Product implements Node & HasMetafields {
    id: ID!
    title: String
    maybe: String
    must: String!
    metafield(key: String!): Metafield
    variants(first: Int!): VariantConnection
  }

  type ProductConnection {
    nodes: [Product!]!
  }

  type Variant implements Node {
    id: ID!
    title: String
  }

  type VariantConnection {
    nodes: [Variant!]!
  }

  type Query {
    products(first: Int): ProductConnection
    nodes(ids: [ID!]!): [Node]!
    node(id: ID!): Node
    noResolver: String
  }

  type WriteValuePayload {
    value: String
  }

  type Mutation {
    writeValue(value: String!): WriteValuePayload
  }
SCHEMA

SCHEMA = GraphQL::Schema.from_definition(SDL)

class WriteValueResolver < GraphQL::BreadthExec::FieldResolver
  def resolve(objects, _args, _ctx, _scope)
    objects.each { _1["writeValue"]["value"] = _args["value"] }
    objects.map { _1["writeValue"] }
  end
end

class SimpleLoader < GraphQL::BreadthExec::Loader
  def perform(keys)
    keys
  end
end

class DeferredHashResolver < GraphQL::BreadthExec::FieldResolver
  def initialize(key)
    @key = key
  end

  def resolve(objects, _args, _ctx, scope)
    scope.defer(SimpleLoader, group: "a", keys: objects.map { _1[@key] })
  end
end

class SimpleHashSource < GraphQL::Dataloader::Source
  def initialize(hash)
    @hash = hash
  end

  def fetch(keys)
    [@hash.fetch(keys.first)]
  end
end

class SimpleHashBatchLoader < GraphQL::Batch::Loader
  def initialize(hash)
    @hash = hash
  end

  def perform(keys)
    keys.each { |key| fulfill(key, @hash.fetch(key)) }
  end
end

BREADTH_RESOLVERS = {
  **GraphQL::BreadthExec::Introspection::TYPE_RESOLVERS,
  "Node" => {
    "id" => GraphQL::BreadthExec::HashKeyResolver.new("id"),
    "__type__" => ->(obj, ctx) { ctx[:query].get_type(obj["__typename__"]) },
  },
  "HasMetafields" => {
    "metafield" => GraphQL::BreadthExec::HashKeyResolver.new("metafield"),
    "__type__" => ->(obj, ctx) { ctx[:query].get_type(obj["__typename__"]) },
  },
  "Metafield" => {
    "key" => GraphQL::BreadthExec::HashKeyResolver.new("key"),
    "value" => GraphQL::BreadthExec::HashKeyResolver.new("value"),
  },
  "Product" => {
    "id" => GraphQL::BreadthExec::HashKeyResolver.new("id"),
    "title" => GraphQL::BreadthExec::HashKeyResolver.new("title"),
    "maybe" => GraphQL::BreadthExec::HashKeyResolver.new("maybe"),
    "must" => GraphQL::BreadthExec::HashKeyResolver.new("must"),
    "variants" => GraphQL::BreadthExec::HashKeyResolver.new("variants"),
    "metafield" => GraphQL::BreadthExec::HashKeyResolver.new("metafield"),
  },
  "ProductConnection" => {
    "nodes" => GraphQL::BreadthExec::HashKeyResolver.new("nodes"),
  },
  "Variant" => {
    "id" => GraphQL::BreadthExec::HashKeyResolver.new("id"),
    "title" => GraphQL::BreadthExec::HashKeyResolver.new("title"),
  },
  "VariantConnection" => {
    "nodes" => GraphQL::BreadthExec::HashKeyResolver.new("nodes"),
  },
  "WriteValuePayload" => {
    "value" => GraphQL::BreadthExec::HashKeyResolver.new("value"),
  },
  "Query" => {
    **GraphQL::BreadthExec::Introspection::ENTRYPOINT_RESOLVERS,
    "products" => GraphQL::BreadthExec::HashKeyResolver.new("products"),
    "nodes" => GraphQL::BreadthExec::HashKeyResolver.new("nodes"),
    "node" => GraphQL::BreadthExec::HashKeyResolver.new("node"),
  },
  "Mutation" => {
    "writeValue" => WriteValueResolver.new,
  },
}.freeze

BREADTH_DEFERRED_RESOLVERS = {
  "Node" => {
    "id" => DeferredHashResolver.new("id"),
    "__type__" => ->(obj, ctx) { ctx[:query].get_type(obj["__typename__"]) },
  },
  "HasMetafields" => {
    "metafield" => DeferredHashResolver.new("metafield"),
    "__type__" => ->(obj, ctx) { ctx[:query].get_type(obj["__typename__"]) },
  },
  "Metafield" => {
    "key" => DeferredHashResolver.new("key"),
    "value" => DeferredHashResolver.new("value"),
  },
  "Product" => {
    "id" => DeferredHashResolver.new("id"),
    "title" => DeferredHashResolver.new("title"),
    "maybe" => DeferredHashResolver.new("maybe"),
    "must" => DeferredHashResolver.new("must"),
    "variants" => DeferredHashResolver.new("variants"),
    "metafield" => DeferredHashResolver.new("metafield"),
  },
  "ProductConnection" => {
    "nodes" => DeferredHashResolver.new("nodes"),
  },
  "Variant" => {
    "id" => DeferredHashResolver.new("id"),
    "title" => DeferredHashResolver.new("title"),
  },
  "VariantConnection" => {
    "nodes" => DeferredHashResolver.new("nodes"),
  },
  "WriteValuePayload" => {
    "value" => DeferredHashResolver.new("value"),
  },
  "Query" => {
    "products" => DeferredHashResolver.new("products"),
    "nodes" => DeferredHashResolver.new("nodes"),
    "node" => DeferredHashResolver.new("node"),
  },
  "Mutation" => {
    "writeValue" => WriteValueResolver.new,
  },
}.freeze

DEPTH_RESOLVERS = {
  "Product" => {
    "id" => ->(obj) { obj["id"] },
    "title" => ->(obj) { obj["title"] },
    "variants" => ->(obj) { obj["variants"] },
  },
  "ProductConnection" => {
    "nodes" => ->(obj) { obj["nodes"] },
  },
  "Variant" => {
    "id" => ->(obj) { obj["id"] },
    "title" => ->(obj) { obj["title"] },
  },
  "VariantConnection" => {
    "nodes" => ->(obj) { obj["nodes"] },
  },
  "Query" => {
    "products" => ->(obj) { obj["products"] },
  },
}.freeze

GEM_RESOLVERS = {
  "Product" => {
    "id" => ->(obj, args, ctx) { obj["id"] },
    "title" => ->(obj, args, ctx) { obj["title"] },
    "variants" => ->(obj, args, ctx) { obj["variants"] },
  },
  "ProductConnection" => {
    "nodes" => ->(obj, args, ctx) { obj["nodes"] },
  },
  "Variant" => {
    "id" => ->(obj, args, ctx) { obj["id"] },
    "title" => ->(obj, args, ctx) { obj["title"] },
  },
  "VariantConnection" => {
    "nodes" => ->(obj, args, ctx) { obj["nodes"] },
  },
  "Query" => {
    "products" => ->(obj, args, ctx) { obj["products"] },
  },
}.freeze

GEM_LAZY_RESOLVERS = {
  "Product" => {
    "id" => ->(obj, args, ctx) { -> { obj["id"] } },
    "title" => ->(obj, args, ctx) { -> { obj["title"] } },
    "variants" => ->(obj, args, ctx) { -> { obj["variants"] } },
  },
  "ProductConnection" => {
    "nodes" => ->(obj, args, ctx) { -> { obj["nodes"] } },
  },
  "Variant" => {
    "id" => ->(obj, args, ctx) { -> { obj["id"] } },
    "title" => ->(obj, args, ctx) { -> { obj["title"] } },
  },
  "VariantConnection" => {
    "nodes" => ->(obj, args, ctx) { -> { obj["nodes"] } },
  },
  "Query" => {
    "products" => ->(obj, args, ctx) { -> { obj["products"] } },
  },
}.freeze

GEM_DATALOADER_RESOLVERS = {
  "Product" => {
    "id" => ->(obj, args, ctx) { ctx.dataloader.with(SimpleHashSource, obj).load("id") },
    "title" => ->(obj, args, ctx) { ctx.dataloader.with(SimpleHashSource, obj).load("title") },
    "variants" => ->(obj, args, ctx) { ctx.dataloader.with(SimpleHashSource, obj).load("variants") },
  },
  "ProductConnection" => {
    "nodes" => ->(obj, args, ctx) { ctx.dataloader.with(SimpleHashSource, obj).load("nodes") },
  },
  "Variant" => {
    "id" => ->(obj, args, ctx) { ctx.dataloader.with(SimpleHashSource, obj).load("id") },
    "title" => ->(obj, args, ctx) { ctx.dataloader.with(SimpleHashSource, obj).load("title") },
  },
  "VariantConnection" => {
    "nodes" => ->(obj, args, ctx) { ctx.dataloader.with(SimpleHashSource, obj).load("nodes") },
  },
  "Query" => {
    "products" => ->(obj, args, ctx) { ctx.dataloader.with(SimpleHashSource, obj).load("products") },
  },
}.freeze

GEM_BATCH_LOADER_RESOLVERS = {
  "Product" => {
    "id" => ->(obj, args, ctx) { SimpleHashBatchLoader.for(obj).load("id") },
    "title" => ->(obj, args, ctx) { SimpleHashBatchLoader.for(obj).load("title") },
    "variants" => ->(obj, args, ctx) { SimpleHashBatchLoader.for(obj).load("variants") },
  },
  "ProductConnection" => {
    "nodes" => ->(obj, args, ctx) { SimpleHashBatchLoader.for(obj).load("nodes") },
  },
  "Variant" => {
    "id" => ->(obj, args, ctx) { SimpleHashBatchLoader.for(obj).load("id") },
    "title" => ->(obj, args, ctx) { SimpleHashBatchLoader.for(obj).load("title") },
  },
  "VariantConnection" => {
    "nodes" => ->(obj, args, ctx) { SimpleHashBatchLoader.for(obj).load("nodes") },
  },
  "Query" => {
    "products" => ->(obj, args, ctx) { SimpleHashBatchLoader.for(obj).load("products") },
  },
}.freeze

BASIC_DOCUMENT = %|{
  products(first: 3) {
    nodes {
      id
      title
      variants(first: 5) {
        nodes {
          id
          title
        }
      }
    }
  }
}|

BASIC_SOURCE = {
  "products" => {
    "nodes" => [{
      "id" => "1",
      "title" => "Apple",
      "variants" => {
        "nodes" => [
          { "id" => "1", "title" => "Large" },
          { "id" => "2", "title" => "Small" },
        ],
      },
    }, {
      "id" => "2",
      "title" => "Banana",
      "variants" => {
        "nodes" => [
          { "id" => "3", "title" => "Large" },
          { "id" => "4", "title" => "Small" },
        ],
      },
    }],
  },
}
