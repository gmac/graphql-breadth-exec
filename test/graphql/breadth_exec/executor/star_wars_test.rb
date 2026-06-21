# frozen_string_literal: true

require "test_helper"

class GraphQL::BreadthExec::Executor::StarWarsTest < Minitest::Test
  def test_correctly_identifies_r2d2_as_the_hero
    result = execute_star_wars <<~GRAPHQL
      query HeroNameQuery {
        hero {
          name
        }
      }
    GRAPHQL

    assert_equal({ "data" => { "hero" => { "name" => "R2-D2" } } }, result)
  end

  def test_allows_query_for_id_and_friends_of_r2d2
    result = execute_star_wars <<~GRAPHQL
      query HeroNameAndFriendsQuery {
        hero {
          id
          name
          friends {
            name
          }
        }
      }
    GRAPHQL

    expected = {
      "data" => {
        "hero" => {
          "id" => "2001",
          "name" => "R2-D2",
          "friends" => [
            { "name" => "Luke Skywalker" },
            { "name" => "Han Solo" },
            { "name" => "Leia Organa" },
          ],
        },
      },
    }

    assert_equal expected, result
  end

  def test_allows_query_for_friends_of_friends_of_r2d2
    result = execute_star_wars <<~GRAPHQL
      query NestedQuery {
        hero {
          name
          friends {
            name
            appearsIn
            friends {
              name
            }
          }
        }
      }
    GRAPHQL

    expected = {
      "data" => {
        "hero" => {
          "name" => "R2-D2",
          "friends" => [
            {
              "name" => "Luke Skywalker",
              "appearsIn" => ["NEWHOPE", "EMPIRE", "JEDI"],
              "friends" => [
                { "name" => "Han Solo" },
                { "name" => "Leia Organa" },
                { "name" => "C-3PO" },
                { "name" => "R2-D2" },
              ],
            },
            {
              "name" => "Han Solo",
              "appearsIn" => ["NEWHOPE", "EMPIRE", "JEDI"],
              "friends" => [
                { "name" => "Luke Skywalker" },
                { "name" => "Leia Organa" },
                { "name" => "R2-D2" },
              ],
            },
            {
              "name" => "Leia Organa",
              "appearsIn" => ["NEWHOPE", "EMPIRE", "JEDI"],
              "friends" => [
                { "name" => "Luke Skywalker" },
                { "name" => "Han Solo" },
                { "name" => "C-3PO" },
                { "name" => "R2-D2" },
              ],
            },
          ],
        },
      },
    }

    assert_equal expected, result
  end

  def test_allows_query_for_character_directly_using_id
    result = execute_star_wars <<~GRAPHQL
      query FetchLukeQuery {
        human(id: "1000") {
          name
        }
      }
    GRAPHQL

    assert_equal({ "data" => { "human" => { "name" => "Luke Skywalker" } } }, result)
  end

  def test_allows_query_using_variable
    result = execute_star_wars <<~GRAPHQL, variables: { "someId" => "1002" }
      query FetchSomeIDQuery($someId: String!) {
        human(id: $someId) {
          name
        }
      }
    GRAPHQL

    assert_equal({ "data" => { "human" => { "name" => "Han Solo" } } }, result)
  end

  def test_returns_null_for_invalid_id
    result = execute_star_wars <<~GRAPHQL, variables: { "id" => "not a valid id" }
      query HumanQuery($id: String!) {
        human(id: $id) {
          name
        }
      }
    GRAPHQL

    assert_equal({ "data" => { "human" => nil } }, result)
  end

  def test_allows_aliases
    result = execute_star_wars <<~GRAPHQL
      query FetchLukeAndLeiaAliased {
        luke: human(id: "1000") {
          name
        }
        leia: human(id: "1003") {
          name
        }
      }
    GRAPHQL

    expected = {
      "data" => {
        "luke" => { "name" => "Luke Skywalker" },
        "leia" => { "name" => "Leia Organa" },
      },
    }

    assert_equal expected, result
  end

  def test_allows_fragments_to_avoid_duplicating_content
    result = execute_star_wars <<~GRAPHQL
      query UseFragment {
        luke: human(id: "1000") {
          ...HumanFragment
        }
        leia: human(id: "1003") {
          ...HumanFragment
        }
      }

      fragment HumanFragment on Human {
        name
        homePlanet
      }
    GRAPHQL

    expected = {
      "data" => {
        "luke" => { "name" => "Luke Skywalker", "homePlanet" => "Tatooine" },
        "leia" => { "name" => "Leia Organa", "homePlanet" => "Alderaan" },
      },
    }

    assert_equal expected, result
  end

  def test_allows_typename_for_abstract_results
    result = execute_star_wars <<~GRAPHQL
      query CheckTypeOfR2 {
        hero {
          __typename
          name
        }
      }
    GRAPHQL

    assert_equal({ "data" => { "hero" => { "__typename" => "Droid", "name" => "R2-D2" } } }, result)
  end

  def test_allows_typename_to_change_with_arguments
    result = execute_star_wars <<~GRAPHQL
      query CheckTypeOfLuke {
        hero(episode: EMPIRE) {
          __typename
          name
        }
      }
    GRAPHQL

    assert_equal({ "data" => { "hero" => { "__typename" => "Human", "name" => "Luke Skywalker" } } }, result)
  end

  def test_reports_error_on_accessing_secret_backstory
    result = execute_star_wars <<~GRAPHQL
      query HeroNameQuery {
        hero {
          name
          secretBackstory
        }
      }
    GRAPHQL

    expected = {
      "data" => {
        "hero" => {
          "name" => "R2-D2",
          "secretBackstory" => nil,
        },
      },
      "errors" => [
        {
          "message" => "secretBackstory is secret.",
          "path" => ["hero", "secretBackstory"],
          "locations" => [{ "line" => 4, "column" => 5 }],
        },
      ],
    }

    assert_equal expected, result
  end

  def test_reports_error_on_accessing_secret_backstory_in_a_list
    result = execute_star_wars <<~GRAPHQL
      query HeroNameQuery {
        hero {
          name
          friends {
            name
            secretBackstory
          }
        }
      }
    GRAPHQL

    expected = {
      "data" => {
        "hero" => {
          "name" => "R2-D2",
          "friends" => [
            { "name" => "Luke Skywalker", "secretBackstory" => nil },
            { "name" => "Han Solo", "secretBackstory" => nil },
            { "name" => "Leia Organa", "secretBackstory" => nil },
          ],
        },
      },
      "errors" => [
        {
          "message" => "secretBackstory is secret.",
          "path" => ["hero", "friends", 0, "secretBackstory"],
          "locations" => [{ "line" => 6, "column" => 7 }],
        },
        {
          "message" => "secretBackstory is secret.",
          "path" => ["hero", "friends", 1, "secretBackstory"],
          "locations" => [{ "line" => 6, "column" => 7 }],
        },
        {
          "message" => "secretBackstory is secret.",
          "path" => ["hero", "friends", 2, "secretBackstory"],
          "locations" => [{ "line" => 6, "column" => 7 }],
        },
      ],
    }

    assert_equal expected, result
  end

  def test_reports_error_on_accessing_through_an_alias
    result = execute_star_wars <<~GRAPHQL
      query HeroNameQuery {
        mainHero: hero {
          name
          story: secretBackstory
        }
      }
    GRAPHQL

    expected = {
      "data" => {
        "mainHero" => {
          "name" => "R2-D2",
          "story" => nil,
        },
      },
      "errors" => [
        {
          "message" => "secretBackstory is secret.",
          "path" => ["mainHero", "story"],
          "locations" => [{ "line" => 4, "column" => 5 }],
        },
      ],
    }

    assert_equal expected, result
  end
end
