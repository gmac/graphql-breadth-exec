# Breadth-first GraphQL execution

_**The core algorithm backing Shopify's _GraphQL Cardinal_ engine.** Learn more about the breadth-first GraphQL design advantages in the [blog post](https://shopify.engineering/faster-breadth-first-graphql-execution). For a TypeScript port, see [graphql-breadth-js](https://github.com/gmac/graphql-breadth-js)._

* Runs field executions breadth-first, layer by layer (versus depth-first, tree by tree).
* Individual resolvers are implicitly batched.
* Lazy resolvers sharing I/O bind entire object sets to a single promise.
* Processes via queuing rather than recursion.

```
ruby 3.2.1 (2023-02-08 revision 31819e82c8) +YJIT [arm64-darwin23]

Non-lazy comparison:
graphql-breadth: 1000 x 3 scalars:     1257.1 i/s
graphql-ruby resolve_batch: 1000 x 3 scalars:      773.2 i/s - 1.63x  slower
graphql-ruby classic: 1000 x 3 scalars:      102.0 i/s - 12.32x  slower

Lazy comparison:
graphql-breadth LazyLoader: 1000 x 1 lazy scalar:     2469.5 i/s
graphql-ruby execute_next + dataloader: 1000 x 1 lazy scalar:      533.1 i/s - 4.63x  slower
graphql-ruby execute_next + graphql-batch: 1000 x 1 lazy scalar:      291.7 i/s - 8.47x  slower
graphql-ruby graphql-batch: 1000 x 1 lazy scalar:      178.7 i/s - 13.82x  slower
graphql-ruby dataloader: 1000 x 1 lazy scalar:      114.6 i/s - 21.56x  slower
```

# Support

The execution algorithm is proven at scale in production. This implementation still has some limitations:

* Uses GraphQL Ruby schemas.
* Currently no built-in validation or analysis, do it ahead of time.
* Supports incremental `@defer` and `@stream` through the `incremental_result` entry point.
* Supports input validations, but NOT input transformations (ie: "prepare" hooks).

# Usage

## Execute a query

```ruby
executor = GraphQL::Breadth::Executor.new(
  MyGraphQLSchema,
  GraphQL.parse(document),
  root_object: { ... },
  variables: { ... },
  context: { ... },
  tracers: [ ... ],
)

result = executor.result
```

## Execution taxonomy

A request document gets built into an execution tree. This taxonomy is provided during execution for sequencing actions. A request like this:

```graphql
query {
  products(first: 10) {
    nodes {
      id
      title
    }
  }
}
```

Gets built into an execution tree structured as the following pseudocode. Object scopes own their selected fields; non-leaf fields have planned child scopes that are entered after the field resolves objects:

```ruby
query_scope = ExecutionScope.new(parent_type: QueryRoot)
products_field = ExecutionField.new(key: "products", scope: query_scope)

product_connection_scope = ExecutionScope.new(parent_type: ProductConnection, parent_field: products_field)
nodes_field = ExecutionField.new(key: "nodes", scope: product_connection_scope)

product_scope = ExecutionScope.new(parent_type: Product, parent_field: nodes_field)
id_field = ExecutionField.new(key: "id", scope: product_scope)
title_field = ExecutionField.new(key: "title", scope: product_scope)
```

This taxonomy provides the following API, which is useful while writing resolver behaviors:

* **`ExecutionField`**: represents a field to execute within a resolved object scope.
  - `path`: the selection path leading to the field, composed of namespaces with no list indices.
  - `schema_path`: the schema path leading to the field, using schema field names rather than response aliases.
  - `key`: the namespace assigned by the field's selection alias or definition name.
  - `name`: the field's schema name.
  - `type`: the GraphQL return type of the field, may be abstract with non-null and list wrappers.
  - `arguments`: a frozen hash of arguments provided to the selection. Argument keys are `:snake_case` symbols. Argument transformations are intentionally not supported (i.e. the input "prepare" hook); argument formatting should be done holistically in the resolver.
  - `mutable_arguments`: a mutable clone of the arguments hash that can be modified.
  - `definition`: the associated GraphQL field definition. For schema reference only (avoid repurposing legacy implementation details).
  - `scope`: the parent execution scope that this field belongs to.
  - `parent_type`: the GraphQL object type that owns the field.
  - `planning_root`: the highest scope that still accepts planning actions while this field is being planned.
  - `resolve_all(<value>)`: resolves a value mapped to all field objects. Useful for early returns.
  - `preload(<LazyLoader>, keys: [...]?, args: { ... }?)`: Registers a lazy preloader to run before the field executes. May only be called by field planner methods.
  - `lazy(loader_class: <LazyLoader>, keys: [...], args: { ... }?)`: defers to lazy execution and returns a Promise. Similar to GraphQL Batch with some fundamental changes, see [documentation](#lazy-resolvers). May only be called by field resolver methods.
  - `await_all([...promises])`: combines several execution promises and resolves when all are fulfilled.
  - `attributes`: a hash intended for local caching and freeform planning notes.
  - `attribute(<name>)`: reads an attribute without allocating storage.
  - `attribute?(<name>)`: checks an attribute without allocating storage.
* **`ExecutionScope`**: represents a resolved object scope with a known concrete object type.
  - `path`: selection path leading to the scope, composed of namespaces with no list indices.
  - `schema_path`: schema path leading to the scope.
  - `parent`: the execution scope above this one.
  - `parent_field`: the execution field in the parent scope that opened this scope.
  - `parent_type`: the GraphQL object type of the scope. This is always a resolved object type, never an abstract interface or union.
  - `abstraction`: for scopes resolved through an interface or union, this details characteristics of that abstraction.
  - `planning_root`: the highest scope that still accepts planning actions while this scope is being planned.
  - `preload(<LazyLoader>, keys: [...]?, args: { ... }?)`: Registers a lazy preloader to run before the scope executes. May only be called by planner methods.
  - `attributes`: a hash intended for local caching and freeform planning notes.
  - `attribute(<name>)`: reads an attribute without allocating storage.
  - `attribute?(<name>)`: checks an attribute without allocating storage.

**Planning traverses each concrete execution tree from the bottom-up**. This is intentional because top-down planning cannot see through unresolved abstractions; once an abstract field resolves to concrete object types, its newly built subtree gets its own bottom-up planning pass.

## Field resolvers

For each field implementation, set up a `GraphQL::Breadth::FieldResolver` or use a [resolver keyword](#resolver-keywords):

```ruby
class MyFieldResolver < GraphQL::Breadth::FieldResolver
   def resolve(exec_field, context)
      exec_field.map_objects { |object| object.some_method }
   end
end
```

A field resolver receives:

* `exec_field`: the execution field providing resources for the scope with [many useful properties](#execution-taxonomy), most importantly:
   - `exec_field.objects`: the set of objects being resolved.
   - `exec_field.arguments`: a hash of resolved arguments provided to the field.
* `context`: the request context.

A resolver **must return a mapped set of results** for the field's objects, or return an execution promise from [lazy loading](#lazy-resolvers). To attach a field resolver to a field, use the `GraphQL::Breadth::HasBreadthResolver` field mixin:

```ruby
class BaseField < GraphQL::Schema::Field
  include GraphQL::Breadth::HasBreadthResolver::Field
end

class BaseObject < GraphQL::Schema::Object
  field_class BaseField
end

class MyObject < BaseObject
  field :featured_products, -> { [Product] } do |f|
    f.breadth_resolver = MyFieldResolver.new
  end
end
```

Resolver classes may also be assigned directly; they are instantiated when assigned. If a schema field does not provide `breadth_resolver`, the executor falls back to the `resolvers:` map passed to `GraphQL::Breadth::Executor.new`, keyed by GraphQL type name and field name.

### Built-in resolvers

The core library includes several basic resolvers for common needs:

* `GraphQL::Breadth::MethodResolver.new(:method_to_call, ...)` (chained methods)
* `GraphQL::Breadth::HashKeyResolver.new("some_key")` (symbol or string key)
* `GraphQL::Breadth::ValueResolver.new(true)` (static value)
* `GraphQL::Breadth::SelfResolver.new` (resolves original objects)

### Resolver keywords

When using `GraphQL::Breadth::HasBreadthResolver::Field`, `breadth_resolver` may be assigned one of the built-in keyword helpers:

* `:method`: calls a method matching the field's original schema name.
* `:hash_key_symbol`: reads a symbol key matching the field's original schema name.
* `:hash_key_string`: reads a string key matching the field's original schema name.
* `:itself`: resolves the original object.

### Early return

Field resolvers may return early with a value for all objects using `resolve_all`. This is commonly used to resolve `nil` or an eager value across all field objects.

```ruby
class MyFieldResolver < GraphQL::Breadth::FieldResolver
   def resolve(exec_field, context)
      return exec_field.resolve_all(nil) if exec_field.arguments[:key].nil?

      # otherwise... resolve something else
   end
end
```

### Attribute caches

Field resolvers may build resources that could be shared with other fields across their scope. It's easy to share this sort of data using `attributes`. Both execution fields [and their scopes](#execution-taxonomy) support setting attributes:

```ruby
class MyFieldResolver < GraphQL::Breadth::FieldResolver
   def resolve(exec_field, context)
      # cache wrapped objects on the parent scope...
      wrapped_objects = exec_field.scope.attributes[:wrapped_objects] ||= begin
        exec_field.objects.map { |obj| MyWrapper.new(obj) }
      end

      wrapped_objects.map(&:wrapper_method)
   end
end
```

When reading attributes, prefer using `element.attribute(key)` to avoid allocating unnecessary storage.

### Error handling

To error out specific object positions within a field, error instances must be mapped into the field's result set. Use the `handle_or_reraise` helper within a StandardError rescue block to optimally handle raised mapping errors:

```ruby
class MyFieldResolver < GraphQL::Breadth::FieldResolver
   def resolve(exec_field, context)
      exec_field.objects.map do |obj|
        obj.valid? ? obj.my_field : GraphQL::ExecutionError.new("Not valid")
      rescue StandardError => e
        exec_field.handle_or_reraise(e)
      end
   end
end
```

This pattern is so common that it's provided as the `map_objects` helper. Just remember when calling `map_objects` that the results may include inlined error positions:

```ruby
class MyFieldResolver < GraphQL::Breadth::FieldResolver
   def resolve(exec_field, context)
      exec_field.map_objects(&:do_stuff!) # << maps to results OR inlined errors
   end
end
```

Any error raised during field execution _outside_ of a rescued mapping loop will result in all field objects receiving the same error:

```ruby
class MyFieldResolver < GraphQL::Breadth::FieldResolver
   def resolve(exec_field, context)
      raise GraphQL::ExecutionError.new("no key") if exec_field.arguments[:key].nil?

      exec_field.map_objects(&:do_stuff!)
   end
end
```

## Lazy resolvers

Breadth field resolvers receive sets, which provides implicit batching for a single field instance. However, this doesn't take into account the same field loading at multiple document positions, or different fields sharing a query. For example:

```graphql
query {
  product(id: "1") {
    featuredMedia {
      ...on Image { sources } # loads image sources
    }
    media(first: 10) {
      nodes {
        ...on Image { sources } # loads image sources
      }
    }
  }
}
```

In the above, we'll want `Image.sources` to batch across all instances of the field, even at different document depths. LazyLoader solves this – which is breadth's analog to traditional dataloaders. Unlike traditional dataloaders though, a breadth LazyLoader binds entire key sets to a single promise, rather than building 1:1 promises. This dramatically reduces lazy overhead.

### LazyLoader classes

Lazy work is always fulfilled by a `GraphQL::Breadth::LazyLoader` class. A field resolver calls `exec_field.lazy(loader_class:, keys:, args: ...)`, which returns an execution promise. The executor pools all pending promises by loader class and argument set, runs each loader once per lazy wave, then resolves each field with its mapped result set.

```ruby
class ThingLoader < GraphQL::Breadth::LazyLoader
  def perform(ids, context)
    Thing.where(parent_id: ids).find_each do |thing|
      fulfill_key(thing.parent_id, thing)
    end
  end
end

class ThingResolver < GraphQL::Breadth::FieldResolver
  def resolve(exec_field, context)
    exec_field.lazy(
      loader_class: ThingLoader,
      keys: exec_field.objects.map(&:id),
    )
  end
end
```

Within a loader class, call `fulfill_key` to deliver each loaded record. Lazy loaders do not require fulfillment of each provided key; unfulfilled keys resolve as `nil`. You can also scope a loader instance with arguments, and wrap the promised values with post-processing:

```ruby
class GroupedThingLoader < GraphQL::Breadth::LazyLoader
  def initialize(group:)
    super()
    @group = group
  end

  def perform(ids, context)
    Thing.where(parent_id: ids, group: @group).find_each do |thing|
      fulfill_key(thing.parent_id, thing)
    end
  end
end

class GroupedThingResolver < GraphQL::Breadth::FieldResolver
  def resolve(exec_field, _context)
    keys = exec_field.objects.map { |obj| obj.valid? ? obj.id : nil }

    exec_field
      .lazy(loader_class: GroupedThingLoader, args: { group: "a" }, keys: keys)
      .then do |loaded_records|
        loaded_records.map! { |record| record&.my_field }
      end
  end
end
```

Loader instances are cached per executor by `[loader_class, args]`, so fields using the same loader class and arguments share a batch. Fields using different arguments get separate loader instances.

### Nil keys

It's extremely common for a mapped set of lazy keys to have `nil` positions that must be retained to match the resolver's breadth set. These nil keys should almost never be loaded, so they are omitted from batching and resolve as nil by default. If you specifically want to treat nil as a loadable value, specify `load_nil_keys: true`.

```ruby
class MaybeNilKeysResolver < GraphQL::Breadth::FieldResolver
  def resolve(exec_field, _context)
    mapped_keys = exec_field.objects.map { |obj| obj.ready? ? obj.id : nil }

    exec_field.lazy(
      loader_class: ThingLoader,
      keys: mapped_keys,
      load_nil_keys: true,
    )
  end
end
```

### Eager values

In many cases, a resolver can eagerly evaluate the result of some keys. Use `eager_values` to inject pre-resolved values into a lazy loader:

```ruby
class MaskingResolver < GraphQL::Breadth::FieldResolver
  def resolve(exec_field, _context)
    eager_values = {}
    mapped_keys = exec_field.objects.map do |obj|
      # statically resolve "zebra" key as "HORSE"...
      eager_values[obj.key] = "HORSE" if obj.key == "zebra"
      obj.key
    end

    exec_field.lazy(
      loader_class: ThingLoader,
      keys: mapped_keys,
      eager_values: eager_values,
    )
  end
end
```

Eager values are specific to their field instance and will _not_ be shared by fields using the same loader. Eager values override the loader cache for that promise, so a specific field instance may eagerly resolve its own value for a key while other fields sharing the loader still load the key as normal.

### Mapped loaders

When it is cheaper to return a complete mapped result set than to fulfill records individually, implement `map?` and `perform_map`. A mapped loader **must return one result per pending loader key**.

```ruby
class MapLoader < GraphQL::Breadth::LazyLoader
  def map?
    true
  end

  def perform_map(keys, context)
    things_by_key = Thing.where(parent_id: keys).index_by(&:parent_id)
    keys.map { |key| things_by_key[key] }
  end
end
```

### Single-result loaders

For loaders that produce exactly one result for exactly one key, implement `resolve_one?`. Calls using that loader must provide exactly one key, and the promise resolves to a single object rather than an array.

```ruby
class OneThingLoader < GraphQL::Breadth::LazyLoader
  def resolve_one?
    true
  end

  def perform(ids, context)
    thing = Thing.find_by(id: ids.first)
    fulfill_key(ids.first, thing) if thing
  end
end
```

### LazyLoader keys vs identities

Lazy loaders support passing any complex object as loader keys. These complex objects can be reduced to a primitive identity within the loader's internal mapping table using the `identity_for` hook:

```ruby
class IdentityLoader < GraphQL::Breadth::LazyLoader
  def identity_for(key)
    "#{key.path}/#{key.handle}"
  end

  def perform(keys, context)
    Thing.load_by_references(keys).each do |thing|
      fulfill_identity("#{thing.path}/#{thing.handle}", thing)
    end
  end
end
```

Later on, it may be simpler to derive the same identity via the loaded result and deliver it via `fulfill_identity` rather than trying to map the record back to a complex key.

### Awaiting and chaining

Multiple loads can be built and awaited:

```ruby
class AwaitingResolver < GraphQL::Breadth::FieldResolver
  def resolve(exec_field, _context)
    keys = exec_field.objects.map(&:key)

    a = exec_field.lazy(loader_class: PrefixLoader, args: { prefix: "a" }, keys: keys)
    b = exec_field.lazy(loader_class: PrefixLoader, args: { prefix: "b" }, keys: keys)

    exec_field
      .await_all([a, b])
      .then do |results_a, results_b|
        exec_field.objects.map.with_index do |_object, i|
          "#{results_a[i]} + #{results_b[i]}"
        end
      end
  end
end
```

Lazy sequencing can be chained:

```ruby
class ChainingResolver < GraphQL::Breadth::FieldResolver
  def resolve(exec_field, _context)
    exec_field
      .lazy(loader_class: PrefixLoader, args: { prefix: "a" }, keys: exec_field.objects.map(&:key))
      .then { |results_a| exec_field.lazy(loader_class: PrefixLoader, args: { prefix: "b" }, keys: results_a) }
      .then { |results_b| results_b.map { |b| "#{b}-fin" } }
  end
end
```

## Query planning

The breadth executor operates on an [execution tree](#execution-taxonomy) in three phases:

1. The execution tree is built from top-down, omitting abstract positions.
2. A planning pass runs from bottom-up on the constructed tree. Fields may register actions on their ancestors.
3. The final execution pass runs from top-down, performing planned actions when encountered.

These three phases repeat each time an abstract position is resolved to build, plan, and execute its resulting subtree. The planning phase allows fields to consider their place within the execution tree and plan accordingly.

### Planning hooks

A field resolver may define a `plan` method that runs during the field's planning phase. This hook may register preloads and/or make tree annotations. Its return value is never captured or used.

```ruby
class WidgetResolver < GraphQL::Breadth::FieldResolver
  def plan(exec_field, context)
    exec_field.preload(AssociationLazyLoader, args: { association: :sprockets })
  end

  def resolve(exec_field, context)
    # resolve the field...
  end
end
```

### Lazy preloads

Both execution scopes and fields may bind lazy loaders during the planning phase that will perform preloads before the element executes. Use the `preload` method:

```ruby
class AssociationPreload < GraphQL::Breadth::LazyLoader
  def initialize(association:)
    super()
    @association = association
  end

  def perform(objects, context)
    ActiveRecord::Associations::Preloader.new(records: objects, associations: @association).call
    objects.each { |obj| fulfill_key(obj, obj.public_send(@association)) }
  end
end

class WidgetResolver < GraphQL::Breadth::FieldResolver
  def plan(exec_field, context)
    exec_field.preload(AssociationPreload, args: { association: :sprockets })
    # or ...
    exec_field.scope.preload(AssociationPreload, args: { association: :sprockets })
  end
end
```

The `preload` method can ONLY be called from within a `plan` hook and its chained preload callbacks, which all run prior to the element executing. Calling `preload` within a field resolver after execution starts will raise a `LazySequencingError`.

**Preloading Scopes vs Fields**

All fields share objects with their scope, so preloading at either level achieves a similar result. However, the timing is subtly different. Preloading a _scope_ will block entering the scope until its preloads are complete; preloading on a _field_ will only block the field itself while allowing sibling fields in the scope to be traversed, thus allowing the discovery of other batching targets among sibling subtrees.

So – scope preloads are useful for loading authorization dependencies and/or shared context; otherwise field preloads are generally preferable for localizing dependencies and blocking as little eager discovery as possible.

**Preload keys**

The `preload` method does not require loader keys and will use the scope or field's resolved objects as keys by default. You can also manually pass keys, which is useful when chaining:

```ruby
class WidgetResolver < GraphQL::Breadth::FieldResolver
  def plan(exec_field, context)
    exec_field
       # uses the field's resolved objects as keys...
      .preload(AssociationPreload, args: { association: :sprockets })
      .then do |sprockets|
        exec_field
          # manually passes preloaded sprockets as keys...
          .preload(AssociationPreload, args: { association: :prices }, keys: sprockets)
      end
  end
end
```

### Preload hooks

Some lazy preloads may need to be configured at the time of execution when objects are actually available for a scope or field. The `on_preload` hook may be used during planning to configure preloads in a just-in-time manner.

```ruby
class WidgetResolver < GraphQL::Breadth::FieldResolver
  def plan(exec_field, context)
    exec_field.on_preload do
      widgets = exec_field.objects.grep(Widget)
      exec_field.preload(AssociationLoader, keys: widgets, args: { association: :prices })
    end
  end
end
```

### Planning root

It's useful to use the root scope as a preload target where all fields in the document can pool common work (ex: loading auth dependencies into a context cache). However –  abstract selection branches are planned _lazily after resolution_, at which time the document above their subtree has been sealed and no longer accepts preloads. Use `planning_root` to always locate the highest unplanned scope and operate there:

```ruby
class WidgetResolver < GraphQL::Breadth::FieldResolver
  def plan(exec_field, context)
    exec_field.scope.planning_root.preload(AuthContextLoader, keys: [context[:agent].id])
  end
end
```

While navigating up the execution tree, you may call `allows_preload?` on scopes and fields to check their status. This check always returns false for taxonomy above the current `planning_root`.

### Attribute annotations

It can be useful to make notes about the execution tree while planning. Both execution scopes and fields provide an `attributes` hash for freeform annotations:

```ruby
class WidgetResolver < GraphQL::Breadth::FieldResolver
  def plan(exec_field, context)
    ancestor_scope = exec_field.scope&.parent
    if ancestor_scope && ancestor_scope.parent_type == Sprocket
      ancestor_scope.attributes[:include_widgets_sql] = true
    end
  end
end
```

Once tree annotations are set during the planning phase, field resolvers can respond accordingly to their notes while executing. When reading attributes, prefer using `element.attribute(key)` to avoid allocating unnecessary storage.

## Authorization

The breadth executor includes a authorization model that can be customized as needed. Create a `GraphQL::Breadth::Authorization` subclass and pass it to your executor:

```ruby
class MyAuthorization < GraphQL::Breadth::Authorization
  # ... detail auth behaviors
end

GraphQL::Breadth::Executor.new(
  MyGraphQLSchema,
  GraphQL.parse(document),
  authorization: MyAuthorization,
)
```

Authorization gates access at three grains: permission to access types, permission to access fields, and permission to access resolved objects. These grains are configured with the following authorization method implementations:

* `authorized_type?(type, context, exec_field: nil)`: checks if a type may be accessed before entering a scope of the type, and before executing a field that returns the type.
* `authorized_field?(exec_field, context)`: checks if a field may be accessed before executing its resolver. This should _only_ check if the field itself is authorized; it should NOT consider the field's owner type and/or return type, which are both covered by direct type checks (see above).
* `authorize_objects_in_scope?(exec_scope, context)`: checks if object-level authorization checks should run in this scope.
* `unauthorized_object_indices(exec_scope, context)`: checks authorization on all scope objects, and returns an invalidation map formatted as `Hash[Integer, StandardError?]`. The returned hash maps object indices to their corresponding authorization errors. An empty hash means no objects were invalidated.

## Runtime directives

Breadth execution supports runtime directive behaviors applied to the `QUERY | MUTATION | FIELD` locations. While a schema may define runtime directives in other document locations, these are for AST reference only and provide no execution hooks.

**This is an operation-level directive (`QUERY | MUTATION` locations):**

```graphql
query @inContext(lang: EN) {
  myField
}
```

**These are field-level directives (`FIELD` location):**

```graphql
query {
  thing @language(lang: EN) {
    title
    child @language(lang: FR) {
      title
    }
  }
}
```

To implement a runtime directive, set up a `GraphQL::Breadth::DirectiveResolver` and assign it to the directive class:

```ruby
class LanguageDirectiveResolver < GraphQL::Breadth::DirectiveResolver
  def resolve(exec_directive, context, current_field: nil)
    return if current_field.nil?

    current_field.attributes[:lang] = exec_directive.arguments[:lang]
  end
end

class Language < GraphQL::Schema::Directive
  extend GraphQL::Breadth::HasBreadthResolver::Directive

  graphql_name("language")
  argument :lang, String, required: true
  locations QUERY, MUTATION, FIELD

  self.breadth_resolver = LanguageDirectiveResolver.new
end
```

### Wrapping directives

Directive resolvers can be configured as block wrappers around all of GraphQL execution (QUERY / MUTATION), or around the execution of a field (FIELD). Wrapping is disabled by default because it adds overhead. To enable wrapping for a specific directive, enable it for the resolver and include a `yield` in its resolver, or pass the resolver `&block` forward:

```ruby
class InContextDirectiveResolver < GraphQL::Breadth::DirectiveResolver
  def initialize
    super(wraps: true)
  end

  def resolve(exec_directive, context, current_field: nil, &block)
    MyI18N.with_context(exec_directive.arguments[:lang], &block) # << must yield
  end
end
```

**Return note:** wrapping directives must return their block result; non-wrapping directives have no return expectations.

**Lazy loading note:** fields are only wrapped by directives during their primary execution pass. If a wrapped field defers to a lazy loader, it must pass any directive state as an argument to the loader. This both preserves the state and assures the field doesn't batch with other fields of different state. Wrapping at the root operation level assigns global execution state that is consistent across both eager and lazy field executions.

### Cascading directives

Breadth execution runs field resolvers via flat queuing rather than recursively, which changes conventional expectations around tree nesting slightly. Consider this example:

```graphql
query {
  a @language(lang: EN) {
    title
    b {
      title
    }
    c @language(lang: FR) {
      title
    }
  }
}
```

We expect `a` to assign a base language of `EN` that `b` inherits, and then `c` overrides with a more specific setting. Breadth execution achieves this by marking directives as _cascading_. A cascading directive will be passed down to all of its child fields within a stacking queue. A field execution then runs all directives that it inherited in the order they were queued, followed by any directives defined on the field itself.

```ruby
class LanguageDirectiveResolver < GraphQL::Breadth::DirectiveResolver
  def initialize
    super(cascades: true)
  end

  def resolve(exec_directive, context, current_field: nil)
    return if current_field.nil?

    # repeatedly write each cascading directive's value onto the field; last one wins...
    current_field.attributes[:lang] = exec_directive.arguments[:lang]
  end
end
```

This architecture makes cascading resolvers run repeatedly on every field in a subtree, rather than just once at the top of the owning field's subtree. This pattern is more granular and generally safer for isolation and parallelism, though has more resolver churn than a typical depth traversal so should be used accordingly.

## Incremental results (`@defer` and `@stream`)

Query and mutation operations that may contain `@defer` or `@stream` should use `incremental_result`. This always returns a `GraphQL::Breadth::Incremental::Result`, even when the operation has no active incremental work:

```ruby
result = executor.incremental_result

deliver(result.initial_result)

if result.incremental?
  result.subsequent_results.each do |payload|
    deliver(payload)
  end
end
```

When no incremental work is active, `initial_result` is the normal GraphQL result hash and `incremental?` is false. When incremental work is active, `initial_result` includes pending records and `hasNext`, and `subsequent_results` yields later incremental payloads.

The basic and incremental entry points are intentionally strict. Call either `result` OR `incremental_result` for a query or mutation executor depending on the request's support for incremental delivery (ex: multi-part and SSE requests); switching entry points after execution has started raises an implementation error.

### Streaming lists

Fields that support `@stream` must opt into the list stream API. The ordinary `resolve` method remains responsible for non-incremental execution. When a stream directive is active, the executor creates a `ListStreamField` for the field instance and calls `resolve_list_stream` for each stream installment.

```ruby
class ProductNodesResolver < GraphQL::Breadth::FieldResolver
  def stream?
    true
  end

  def resolve(exec_field, context)
    exec_field.map_objects { |connection| connection.nodes }
  end

  def resolve_list_stream(field, context)
    field.pending_entries.map do |entry|
      connection = entry.object
      object_state = entry.object_state
      cursor = object_state[:cursor]
      page_size = field.limit || 25

      page = ProductLoader.load_page(
        connection,
        first: page_size,
        after: cursor,
        context: context,
      )

      object_state[:cursor] = page.end_cursor

      GraphQL::Breadth::ListStreamChunk.new(
        items: page.nodes,
        complete: !page.has_next_page?,
      )
    end
  end
end
```

`resolve_list_stream` receives the `GraphQL::Breadth::Executor::ListStreamField` for the active stream instance. Its `pending_entries` are only the parent objects that still have active stream deliveries. Once an entry returns a complete chunk, it is dropped from the field's `pending_entries` and will not be present in later calls. This lets resolvers keep batching active streams together while avoiding repeated work for streams that have already finished.

The method arguments are:

* `field`: the `GraphQL::Breadth::Executor::ListStreamField` for this stream instance.
* `context`: the request context.

`ListStreamField` delegates the field shape from the original `ExecutionField`: `arguments`, `mutable_arguments`, `type`, `nodes`, `selections`, `key`, `name`, and `path` all refer to the streamed schema field. It also exposes stream-specific state:

* `pending_entries`: active `GraphQL::Breadth::Incremental::ListStreamEntry` objects.
* `state`: the shared field-instance state hash.
* `limit`: the directive's `initialCount` when preparing the initial result, then `nil` for later calls.
* `iteration`: the zero-based call count for this stream field.

Each `ListStreamEntry` exposes:

* `object`: the active parent object for this stream installment.
* `object_state`: a persistent state hash for that specific object.

`ListStreamField` also supports the same execution helpers used by fields: `lazy(loader_class:, keys:, args: ...)`, `await_all`, `resolve_all`, `handle_or_reraise`, and `attributes`. Lazy stream resolvers should call `field.lazy`, not `exec_field.lazy`, because stream installments are resumed independently from the original field execution.

Return one result per active object. A `GraphQL::Breadth::ListStreamChunk` is the explicit form: `items:` are emitted in this installment and `complete:` controls whether that object's stream remains active. Returning an array is shorthand for "emit these items and keep going" unless the array is empty, in which case the object is complete. Returning `nil` completes the object without emitting items.

If the directive uses `@stream(initialCount: 0)`, the initial result includes no list items and does not call `resolve_list_stream` while building the initial response. The first resolver call happens while preparing the first subsequent payload, with `limit: nil`.

Streaming resolvers can batch the active entries through a lazy loader:

```ruby
class ProductNodesResolver < GraphQL::Breadth::FieldResolver
  def stream?
    true
  end

  def resolve(exec_field, context)
    exec_field.map_objects { |connection| connection.nodes }
  end

  def resolve_list_stream(field, context)
    page_size = field.limit || 10

    field.lazy(
      loader_class: ProductPageLoader,
      keys: field.pending_entries,
      args: { limit: page_size },
    ).then do |all_results|
      field.pending_entries.map.with_index do |entry, index|
        results = all_results[index]
        entry.object_state[:cursor] = results.last&.id

        GraphQL::Breadth::ListStreamChunk.new(
          items: results,
          complete: results.size < page_size,
        )
      end
    end
  end
end
```

## Subscriptions

Query and mutation execution use `result`, which always returns a normal GraphQL result hash. Subscription operations use `subscribe`, which returns a `GraphQL::Breadth::SubscriptionResponseStream` on successful source setup, or a normal GraphQL result hash for public setup errors. Each entry point is strict about its operation type, matching the `execute` / `subscribe` split in graphql-js: calling `result` (or `incremental_result`) for a subscription operation raises an implementation error, and calling `subscribe` for a query or mutation operation raises an implementation error. A controller that accepts both inspects the operation type and dispatches accordingly:

```ruby
executor = GraphQL::Breadth::Executor.new(
  MyGraphQLSchema,
  GraphQL.parse(document),
  variables: { ... },
  context: { ... },
)

if executor.subscription?
  stream = executor.subscribe
  stream.each do |event_result|
    deliver(event_result)
  end
else
  deliver(executor.result)
end
```

Subscription root fields use two field resolver hooks:

* `subscribe(exec_field, context)` runs once during subscription setup and must return an `Enumerable` or `Enumerator` of source events.
* `resolve(exec_field, context)` runs once per yielded source event. The source event is used as the root object for that event's GraphQL execution.

```ruby
class OnWriteValueResolver < GraphQL::Breadth::FieldResolver
  def subscribe(exec_field, context)
    context[:write_value_events]
  end

  def resolve(exec_field, context)
    exec_field.map_objects(&:itself)
  end
end

class WriteValuePayload < BaseObject
  field :value, String, null: true
end

class Subscription < BaseObject
  field :on_write_value, WriteValuePayload, null: true do |field|
    field.breadth_resolver = OnWriteValueResolver.new
  end
end
```

For a small in-process source stream, any Ruby enumerator is enough:

```ruby
write_value_events = Enumerator.new do |events|
  events << { value: "first" }
  events << { value: "second" }
end

executor = GraphQL::Breadth::Executor.new(
  MyGraphQLSchema,
  GraphQL.parse(%|
    subscription WatchWrites {
      onWriteValue {
        value
      }
    }
  |),
  context: { write_value_events: write_value_events },
)

stream = executor.subscribe
stream.each do |event_result|
  # {"data"=>{"onWriteValue"=>{"value"=>"first"}}}
  # {"data"=>{"onWriteValue"=>{"value"=>"second"}}}
  deliver(event_result)
end
```

Each source event is fulfilled through normal breadth execution, so field resolvers, lazy loading, authorization, directives, abstract type resolution, and error formatting all work as they do for query execution. Errors raised while enumerating the source stream are allowed to propagate to the stream consumer. Promise-backed subscription setup is not supported; `subscribe` should return the source stream synchronously. Returning a promise or any non-enumerable value is an implementation error.
