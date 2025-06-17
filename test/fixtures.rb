SCHEMA = GraphQL::Schema.from_definition(%|
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
  }

  type WriteValuePayload {
    value: String
  }

  type Mutation {
    writeValue(value: String!): WriteValuePayload
  }
|)

class WriteValueResolver < GraphQL::Cardinal::FieldResolver
  def resolve(objects, _args, _ctx, _scope)
    objects.each { _1["writeValue"]["value"] = _args["value"] }
    objects.map { _1["writeValue"] }
  end
end

BREADTH_RESOLVERS = {
  "Node" => {
    "id" => GraphQL::Cardinal::HashKeyResolver.new("id"),
    "__typename" => GraphQL::Cardinal::TypenameResolver.new,
    "__type__" => ->(obj, ctx) { ctx[:query].get_type(obj["__typename__"]) },
  },
  "HasMetafields" => {
    "metafield" => GraphQL::Cardinal::HashKeyResolver.new("metafield"),
    "__typename" => GraphQL::Cardinal::TypenameResolver.new,
    "__type__" => ->(obj, ctx) { ctx[:query].get_type(obj["__typename__"]) },
  },
  "Metafield" => {
    "key" => GraphQL::Cardinal::HashKeyResolver.new("key"),
    "value" => GraphQL::Cardinal::HashKeyResolver.new("value"),
    "__typename" => GraphQL::Cardinal::TypenameResolver.new,
  },
  "Product" => {
    "id" => GraphQL::Cardinal::HashKeyResolver.new("id"),
    "title" => GraphQL::Cardinal::HashKeyResolver.new("title"),
    "maybe" => GraphQL::Cardinal::HashKeyResolver.new("maybe"),
    "must" => GraphQL::Cardinal::HashKeyResolver.new("must"),
    "variants" => GraphQL::Cardinal::HashKeyResolver.new("variants"),
    "metafield" => GraphQL::Cardinal::HashKeyResolver.new("metafield"),
    "__typename" => GraphQL::Cardinal::TypenameResolver.new,
  },
  "ProductConnection" => {
    "nodes" => GraphQL::Cardinal::HashKeyResolver.new("nodes"),
    "__typename" => GraphQL::Cardinal::TypenameResolver.new,
  },
  "Variant" => {
    "id" => GraphQL::Cardinal::HashKeyResolver.new("id"),
    "title" => GraphQL::Cardinal::HashKeyResolver.new("title"),
    "__typename" => GraphQL::Cardinal::TypenameResolver.new,
  },
  "VariantConnection" => {
    "nodes" => GraphQL::Cardinal::HashKeyResolver.new("nodes"),
    "__typename" => GraphQL::Cardinal::TypenameResolver.new,
  },
  "WriteValuePayload" => {
    "value" => GraphQL::Cardinal::HashKeyResolver.new("value"),
    "__typename" => GraphQL::Cardinal::TypenameResolver.new,
  },
  "Query" => {
    "products" => GraphQL::Cardinal::HashKeyResolver.new("products"),
    "nodes" => GraphQL::Cardinal::HashKeyResolver.new("nodes"),
    "node" => GraphQL::Cardinal::HashKeyResolver.new("node"),
    "__typename" => GraphQL::Cardinal::TypenameResolver.new,
  },
  "Mutation" => {
    "writeValue" => WriteValueResolver.new,
    "__typename" => GraphQL::Cardinal::TypenameResolver.new,
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
