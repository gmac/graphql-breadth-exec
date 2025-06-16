SCHEMA = GraphQL::Schema.from_definition(%|
  type Product {
    id: ID!
    title: String
    variants(first: Int!): VariantConnection
  }

  type ProductConnection {
    nodes: [Product!]!
  }

  type Variant {
    id: ID!
    title: String
  }

  type VariantConnection {
    nodes: [Variant!]!
  }

  type Query {
    products(first: Int): ProductConnection
  }
|)

DOCUMENT = GraphQL.parse(%|{
  products(first: 3) {
    nodes {
      id
      variants(first: 5) {
        nodes {
          id
          title
        }
      }
    }
  }
  ... {
    products(first: 3) {
      nodes {
        title
      }
    }
  }
}|)

SOURCE = {
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
