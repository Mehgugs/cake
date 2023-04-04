# 🍰 – Effects for Lua

Cake is a simple library for using one-shot effects in lua.

```lua
local cake = require"cake"
local http = require"socket.http"

-- first define all the effects you want to use...
local HttpRequest = cake.effects {
    get = true
}

-- Now write some effectful code
local function size_example()
    -- Ask your caller to perform the `HttpRequest.get` effect.
    local content = coroutine.yield(HttpRequest.get"https://example.com")

    return ("https://example.com is %d bytes"):format(#content)
end

-- To run it we need to handle all the effects:
local function handler(effect)
    -- The (~) operator on effects matches them to their constructor
    if effect ~ HttpRequest.get then
        local url = effect:args() -- any arguments passed into the constructor are available here!
        return http.request(url)
    end
end

local function main()
    local result = cake.run(handler, size_example)
    print(result)
end
```

## Reference

#### *anything* `cake.run(handler, f, ...)`

Runs an effectful function `f` against the effect handler `handler`, returning the final results of `f`.

- *function(effect, cont)* `handler`
  See the notes on effect handlers for more information on this parameter.

- *function* `f`
  An effectful function.

- *anything* `...`
  Arguments to `f`.

#### *table (effect constructors)* `cake.effects(t)`

Accepts a specification of effects and returns a table with the same structure, where all leaves
are effect constructors.

- *table* `t`
  A table whose structure describes the effects you want to implement.

```lua
E = cake.effects{
    foo = {bar = {baz = 1}}, -----> foo = {bar = {baz = effect"foo.bar.baz"}}
    qux = true,              -----> qux = effect"qux"
    quux = "something"       -----> quux = effect"quux"
}
```

Effect constructors can be called to create an effect, and this value can then be yielded to request
the handler performs it.

```lua
coroutine.yield(E.qux(1,2,3))
```

#### *table (effect constructors)* `cake.effects(name) (t)`

If called with a string as the first argument, returns a namespaced
function for creating effect constructors:

```lua
local Delay = cake.effects "Delay" {
    wait = true,
    cancel = true
}
```

#### *table (effects)* `cake.simple`

This table can be used to construct simple (i.e valueless) effects.

```lua
local A = cake.simple.A

function handler(effect)
    if effect == A --[[effect ~ A]] then
        return "effect a"
    end
end

cake.run(handler, function() print(coroutine.yield(A)) end)
-- "effect a"
```

#### *table (effect)* `constructor(...)`

These objects represent effects to be performed by handlers, and are created by effect constructors.
They are simply tagged tables with array content that can be unpacked via a method.

```lua
local Delay = cake.effects "Delay" {
    wait = true,
    cancel = true
}
Delay.wait(5.0) -- constructs an instance of the "wait" effect.
```

#### *table (effect) | nil* `effect ~ Constructor`

Matches an effect with a constructor; returning the effect if it was created by that constructor.

#### *string* `effect.name`

This value is equal to the name of the effect; and can also be used for matching.


#### *anything* `effect:args()`

Unpacks an effect's captured arguments.

```lua
local function handler(effect)
    if effect ~ E.qux then
        local a,b,c = effect:args()
        return a + b + c
    end
end
```

#### *anything...* `handler(effect, cont, abort)`

An effect handler is a function of three parameters: an effect, an effect continuation, and an abort function. If you want to handle an effect, then you do so within this function body
and should return any results of the effect's computation so that they can be fed back
to the requestee. You may also use the `cont` callback to respond instead of returning,
but if you want to respond asynchronously you must return the `wait` sentinel value.
If you return additional arguments after `cake.wait`, they will be propagated to the place where control resumes if possible, for example if you `return cake.wait, "foo"` for `MyAsyncEffect` then `cake.perform` will return `"foo"` when `MyAsyncEffect` is handled.
If this function returns nothing then effect resolution is passed on to an outer coroutine. The abort function can be used to cancel the effectful computation:
```lua
    local MyEffect = cake.atoms.Test

    local function handler(effect, _, abort)
        if effect ~ MyEffect then
            abort("aborted")
        end
    end

    cake.run(handler, function() coroutine.yield(MyEffect) return 5 end)
        --- the run call returns "aborted"
```

When a nested effect is aborted, the inner computation is affected, not its parent:
```lua
local x, y
x = cake.run(handler, function()
    -- cake.pass is just a predefined noop function; forcing resolution to defer to the outer parent.
    y = cake.run(cake.pass, function() coroutine.yield(MyEffect) return 5 end)
    -- control flow resumes here after the handler aborts the 'Test' effect.
    return 6
end)

print(x, y) -- 6    "aborted"
```

#### Notes on nested effects

When managing the control flow of effectful computations you may
find that nesting `cake.run` calls is required. There are multiple helpers
defined which make the various operations on effects easier to manage.

#### *anything* `cake.perform(f)`

Launches a new `cake.run` call in a coroutine, using the currently applied handler.
This is useful if you need to prevent effects from blocking till resolved:

```lua
local cake = require"cake"
local delay = require"delay"
    -- wait(seconds) blocks until `seconds` have elapsed

local function main()
    local thread = cake.perform(function() -- inherits our handler
        delay.wait(5.0)
        print("5 seconds elapsed")
    end)

    delay.wait(3.0)
    print("Waited 3 seconds instead!")
    delay.cancel(thread)
end

cake.start(delay.impl, main)
```

#### Notes on handling effects

When handling effects using `cake.wait` you must take care with how you use the `cont` and `abort` functions; they're not actually functions, but instead are callable values.

This may cause a problem when passing the `cont` "function" into a system callback directly, for example into an event loop written in C. I apologize for this inconvenience.

Value propagation can get confusing when using `cake.wait`, because control has to switch contexts so frequently. I recommend creating some simple effects and observing how the values are returned at various points (i.e what is returned from `cont` after you've `cake.wait`-ed? What about synchronous `abort` and `cont`!?).

If you decide to call `cont` while control is still held by the handler the computation
is processed normally so that a value can be returned for cont and whatever you return from the handler is therefore ignored. You cannot call `cont` multiple times synchronously because the computation was completed by the first call.

