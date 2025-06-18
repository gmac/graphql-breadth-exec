![Cardinal](./images/cardinal.png)

**An (experimental) breadth-first GraphQL executor for Ruby**

Depth-first execution resolves every object field descending down a response tree, while breadth-first visits every _selection position_ once with an aggregated set of objects. A breadth-first approach makes resolver overhead dramatically cheaper when resolvers only scale by the size of the request document rather than the size of the response.

```shell
graphql-ruby: 140002 resolvers
    1.159 (± 0.0%) i/s  (862.55 ms/i) - 6.000 in 5.182856s
graphql-cardinal 140002 resolvers
    19.251 (±10.4%) i/s   (51.95 ms/i) - 95.000 in 5.007853s

Comparison:
graphql-cardinal 140002 resolvers:     19.3 i/s
graphql-ruby: 140002 resolvers:     1.2 i/s - 16.60x  slower
```

### Depth vs. Breadth

GraphQL requests have two dimensions: _depth_ and _breadth_. The depth dimension is finite as defined by the request document, while the breadth dimension scales by the size of the response data (and can grow extremely large).

![Breadth/Depth](./images/breadth-depth.png)

### Depth-first execution

Depth-first execution (the conventional GraphQL execution strategy) resolves every field in the response by descending down the selection tree of every object. This overhead scales linearly as the response size grows, and balloons quickly with added field tracing and instrumentation.

![Depth](./images/depth-first.png)

### Breadth-first execution

Breadth-first resolvers look a little different than we're used to: they recieve `objects` and return a mapped set.

```ruby
def resolve(objects, args, cxt)
  objects.map { ... }
end
```

Breadth-first then runs a single resolver per document selection, and coalesces an array of sources to pass down to the next generation. Now resolver overhead scales by the size of the request document rather than the size of the response data.

![Breadth](./images/breadth-first.png)

While bigger responses will always take longer to process, the workload is almost entirely your own business logic rather than GraphQL execution overhead. Other advantages:

* Eliminates the need for DataLoader promises, because resolvers are inherently batched.
* Executes via flat queuing without deep recursion and huge call stacks.
