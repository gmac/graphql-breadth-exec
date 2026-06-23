# frozen_string_literal: true

STAR_WARS_SDL = <<~GRAPHQL
  enum Episode {
    NEWHOPE
    EMPIRE
    JEDI
  }

  interface Character {
    id: String!
    name: String
    friends: [Character]
    appearsIn: [Episode]
    secretBackstory: String
  }

  type Human implements Character {
    id: String!
    name: String
    friends: [Character]
    appearsIn: [Episode]
    homePlanet: String
    secretBackstory: String
  }

  type Droid implements Character {
    id: String!
    name: String
    friends: [Character]
    appearsIn: [Episode]
    primaryFunction: String
    secretBackstory: String
  }

  type Query {
    hero(episode: Episode): Character
    human(id: String!): Human
    droid(id: String!): Droid
  }
GRAPHQL

STAR_WARS_SCHEMA = GraphQL::Schema.from_definition(STAR_WARS_SDL)

STAR_WARS_DATA = {
  "1000" => {
    "__typename__" => "Human",
    "id" => "1000",
    "name" => "Luke Skywalker",
    "friends" => ["1002", "1003", "2000", "2001"],
    "appearsIn" => ["NEWHOPE", "EMPIRE", "JEDI"],
    "homePlanet" => "Tatooine",
  },
  "1001" => {
    "__typename__" => "Human",
    "id" => "1001",
    "name" => "Darth Vader",
    "friends" => ["1004"],
    "appearsIn" => ["NEWHOPE", "EMPIRE", "JEDI"],
    "homePlanet" => "Tatooine",
  },
  "1002" => {
    "__typename__" => "Human",
    "id" => "1002",
    "name" => "Han Solo",
    "friends" => ["1000", "1003", "2001"],
    "appearsIn" => ["NEWHOPE", "EMPIRE", "JEDI"],
    "homePlanet" => nil,
  },
  "1003" => {
    "__typename__" => "Human",
    "id" => "1003",
    "name" => "Leia Organa",
    "friends" => ["1000", "1002", "2000", "2001"],
    "appearsIn" => ["NEWHOPE", "EMPIRE", "JEDI"],
    "homePlanet" => "Alderaan",
  },
  "1004" => {
    "__typename__" => "Human",
    "id" => "1004",
    "name" => "Wilhuff Tarkin",
    "friends" => ["1001"],
    "appearsIn" => ["NEWHOPE"],
    "homePlanet" => nil,
  },
  "2000" => {
    "__typename__" => "Droid",
    "id" => "2000",
    "name" => "C-3PO",
    "friends" => ["1000", "1002", "1003", "2001"],
    "appearsIn" => ["NEWHOPE", "EMPIRE", "JEDI"],
    "primaryFunction" => "Protocol",
  },
  "2001" => {
    "__typename__" => "Droid",
    "id" => "2001",
    "name" => "R2-D2",
    "friends" => ["1000", "1002", "1003"],
    "appearsIn" => ["NEWHOPE", "EMPIRE", "JEDI"],
    "primaryFunction" => "Astromech",
  },
}.freeze

class StarWarsFriendsResolver < GraphQL::Breadth::FieldResolver
  def resolve(exec_field, _ctx)
    exec_field.map_objects do |character|
      character["friends"].map { |id| STAR_WARS_DATA[id] }
    end
  end
end

class StarWarsSecretBackstoryResolver < GraphQL::Breadth::FieldResolver
  def resolve(exec_field, _ctx)
    exec_field.map_objects_with_index do |_character, index|
      path = exec_field.path.dup
      path.insert(-2, index) if exec_field.objects.length > 1
      GraphQL::Breadth::ExecutionError.new("secretBackstory is secret.", path: path, exec_field: exec_field)
    end
  end
end

class StarWarsHeroResolver < GraphQL::Breadth::FieldResolver
  def resolve(exec_field, _ctx)
    exec_field.map_objects do
      exec_field.arguments[:episode] == "EMPIRE" ? STAR_WARS_DATA["1000"] : STAR_WARS_DATA["2001"]
    end
  end
end

class StarWarsHumanResolver < GraphQL::Breadth::FieldResolver
  def resolve(exec_field, _ctx)
    exec_field.map_objects do
      character = STAR_WARS_DATA[exec_field.arguments[:id]]
      character && character["__typename__"] == "Human" ? character : nil
    end
  end
end

class StarWarsDroidResolver < GraphQL::Breadth::FieldResolver
  def resolve(exec_field, _ctx)
    exec_field.map_objects do
      character = STAR_WARS_DATA[exec_field.arguments[:id]]
      character && character["__typename__"] == "Droid" ? character : nil
    end
  end
end

STAR_WARS_CHARACTER_RESOLVERS = {
  "id" => GraphQL::Breadth::HashKeyResolver.new("id"),
  "name" => GraphQL::Breadth::HashKeyResolver.new("name"),
  "friends" => StarWarsFriendsResolver.new,
  "appearsIn" => GraphQL::Breadth::HashKeyResolver.new("appearsIn"),
  "secretBackstory" => StarWarsSecretBackstoryResolver.new,
}.freeze

STAR_WARS_RESOLVERS = {
  "Character" => {
    **STAR_WARS_CHARACTER_RESOLVERS,
    "__type__" => lambda { |obj, ctx|
      ctx.types.type(obj["__typename__"])
    },
  },
  "Human" => {
    **STAR_WARS_CHARACTER_RESOLVERS,
    "homePlanet" => GraphQL::Breadth::HashKeyResolver.new("homePlanet"),
  },
  "Droid" => {
    **STAR_WARS_CHARACTER_RESOLVERS,
    "primaryFunction" => GraphQL::Breadth::HashKeyResolver.new("primaryFunction"),
  },
  "Query" => {
    "hero" => StarWarsHeroResolver.new,
    "human" => StarWarsHumanResolver.new,
    "droid" => StarWarsDroidResolver.new,
  },
}.freeze

def execute_star_wars(query, variables: {})
  GraphQL::Breadth::Executor.new(
    STAR_WARS_SCHEMA,
    GraphQL.parse(query),
    resolvers: STAR_WARS_RESOLVERS,
    variables: variables,
  ).result
end
