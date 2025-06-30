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

  enum WidgetStatus {
    YES
    NO
  }

  type Widget {
    status: WidgetStatus
  }

  input DimensionInput {
    width: Int = 1
    height: Int = 2
    depth: Int = 3
  }

  input WidgetCreateInput {
    price: Int = 25
    status: String = "ACTIVE"
    dimension: DimensionInput = { height: 25 }
  }

  type Query {
    products(first: Int): ProductConnection
    nodes(ids: [ID!]!, sfooBar:String = "woof"): [Node]!
    node(id: ID!, sfooBar:String = "woof"): Node
    widget: Widget
    noResolver: String
  }

  type WriteValuePayload {
    value: String
  }

  type Mutation {
    writeValue(value: String!): WriteValuePayload
    widgetCreate(input: WidgetCreateInput = {}): Widget
  }
SCHEMA

SCHEMA = GraphQL::Schema.from_definition(SDL)

class WriteValueResolver < GraphQL::Cardinal::FieldResolver
  def resolve(objects, _args, _ctx, _scope)
    objects.each { _1["writeValue"]["value"] = _args["value"] }
    objects.map { _1["writeValue"] }
  end
end

class SimpleLoader < GraphQL::Cardinal::Loader
  def perform(keys)
    keys
  end
end

class DeferredHashResolver < GraphQL::Cardinal::FieldResolver
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
  "Node" => {
    "id" => GraphQL::Cardinal::HashKeyResolver.new("id"),
    "__type__" => ->(obj, ctx) { ctx.query.get_type(obj["__typename__"]) },
  },
  "HasMetafields" => {
    "metafield" => GraphQL::Cardinal::HashKeyResolver.new("metafield"),
    "__type__" => ->(obj, ctx) { ctx.query.get_type(obj["__typename__"]) },
  },
  "Metafield" => {
    "key" => GraphQL::Cardinal::HashKeyResolver.new("key"),
    "value" => GraphQL::Cardinal::HashKeyResolver.new("value"),
  },
  "Product" => {
    "id" => GraphQL::Cardinal::HashKeyResolver.new("id"),
    "title" => GraphQL::Cardinal::HashKeyResolver.new("title"),
    "maybe" => GraphQL::Cardinal::HashKeyResolver.new("maybe"),
    "must" => GraphQL::Cardinal::HashKeyResolver.new("must"),
    "variants" => GraphQL::Cardinal::HashKeyResolver.new("variants"),
    "metafield" => GraphQL::Cardinal::HashKeyResolver.new("metafield"),
  },
  "ProductConnection" => {
    "nodes" => GraphQL::Cardinal::HashKeyResolver.new("nodes"),
  },
  "Variant" => {
    "id" => GraphQL::Cardinal::HashKeyResolver.new("id"),
    "title" => GraphQL::Cardinal::HashKeyResolver.new("title"),
  },
  "VariantConnection" => {
    "nodes" => GraphQL::Cardinal::HashKeyResolver.new("nodes"),
  },
  "WriteValuePayload" => {
    "value" => GraphQL::Cardinal::HashKeyResolver.new("value"),
  },
  "Query" => {
    "products" => GraphQL::Cardinal::HashKeyResolver.new("products"),
    "nodes" => GraphQL::Cardinal::HashKeyResolver.new("nodes"),
    "node" => GraphQL::Cardinal::HashKeyResolver.new("node"),
  },
  "Mutation" => {
    "writeValue" => WriteValueResolver.new,
    "widgetCreate" => GraphQL::Cardinal::HashKeyResolver.new("widgetCreate"),
  },
}.freeze

BREADTH_DEFERRED_RESOLVERS = {
  "Node" => {
    "id" => DeferredHashResolver.new("id"),
    "__type__" => ->(obj, ctx) { ctx.query.get_type(obj["__typename__"]) },
  },
  "HasMetafields" => {
    "metafield" => DeferredHashResolver.new("metafield"),
    "__type__" => ->(obj, ctx) { ctx.query.get_type(obj["__typename__"]) },
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
  "Mutation" => {
    "widgetCreate" => ->(obj, args, ctx) { 
       binding.pry
      "wat?"
     },
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
