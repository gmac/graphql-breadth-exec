# Breadth-first GraphQL execution

_**The original core algorithm prototype of Shopify's GraphQL Cardinal engine**_

Traditional GraphQL implementations execute depth-first, which resolves every field of every object in the response, making resolver actions scale by depth x breadth. In breadth-first execution, we visit every _selection position_ once with an aggregated set of objects. The breadth-first approach is much faster at processing list repetitions due to fewer resolver calls and intermediary promises.

```shell
graphql-ruby: 140002 resolvers
   1.087 (± 0.0%) i/s  (919.76 ms/i) -  6.000 in  5.526807s
graphql-breadth_exec 140002 resolvers
   21.314 (± 9.4%) i/s   (46.92 ms/i) -  108.000 in  5.095015s

Comparison:
graphql-breadth_exec 140002 resolvers:   21.3 i/s
graphql-ruby: 140002 resolvers:   1.1 i/s - 19.60x  slower
```

## Understanding breadth execution

GraphQL requests have two dimensions: _depth_ and _breadth_. The depth dimension is finite as defined by the request document, while the breadth dimension scales by the size of the response data (and can grow extremely large).

![Breadth/Depth](./images/breadth-depth.png)

Depth-first execution (the conventional GraphQL execution strategy) resolves every field of every object in the response using individual subtree traversals. This overhead scales as the response size grows, and balloons quickly with added field tracing.

![Depth](./images/depth-first.png)

By comparison, breadth-first resolvers look a little different than we're used to: they recieve `objects` and return a mapped set.

```ruby
def resolve(objects, args, cxt)
  objects.map { ... }
end
```

Breadth-first then runs a single resolver per document selection, and coalesces an array of sources to pass down to the next generation. Now resolver overhead scales by the size of the request document rather than the size of the response data.

![Breadth](./images/breadth-first.png)

While bigger responses will always take longer to process, the workload is in your own business logic with very little GraphQL execution overhead. The other superpower of breadth execution is its ability to reduce promise overhead. Individual fields arrive batched by default, then when multiple fields pool loading, entire breadth sets can be bound to a single promise rather than building promises for each item in the set.

![Promises](./images/promises.png)

## API

Setup a `GraphQL::BreadthExec::FieldResolver`:

```ruby
class MyFieldResolver < GraphQL::BreadthExec::FieldResolver
   def resolve(objects, args, ctx, scope)
      map_sources(objects) { |obj| obj.my_field }
   end
end
```

A field resolver provides:

* `objects`: the array of objects to resolve the field on.
* `args`: the coerced arguments provided to this selection field.
* `ctx`: the request context.
* `scope`: (experimental) a handle to the execution scope that invokes lazy hooks.

A resolver must return a mapped set of data for the provided objects. Always use the `map_sources` helper for your mapping loop to assure that exceptions are captured properly. You may return errors for a field position by mapping an `ExecutionError` into it:

```ruby
class MyFieldResolver < GraphQL::BreadthExec::FieldResolver
   def resolve(objects, args, ctx, scope)
      map_sources(objects) do |obj|
         obj.valid? ? obj.my_field : GraphQL::BreadthExec::ExecutionError.new("Object field not valid")
      end
   end
end
```

Now setup a resolver map:

```ruby
RESOLVER_MAP = {
  "MyType" => {
    "myField" => MyFieldResolver.new,
  },
  "Query" => {
    "myType" => MyTypeResolver.new,
  },
}.freeze
```

Now parse your schema definition and execute requests:

```ruby
SCHEMA = GraphQL::Schema.from_definition(%|
  type MyType {
    myField: String
  }
  type Query {
    myType: MyType
  }
|)

result = GraphQL::BreadthExec::Executor.new(
   SCHEMA,
   RESOLVER_MAP,
   GraphQL.parse(query),
   {}, # root object
   variables: { ... },
   context: { ... },
   tracers: [ ... ],
).perform
```
