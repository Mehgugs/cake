# 🍰 – Effects for Lua

Cake is a simple library which for using one-shot effects in lua.

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



### `effect`

These objects represent effects to be performed by handlers, and are created by effect constructors.
They are simply tagged tables with array content that can be unpacked via a method.

#### *effect | nil* `effect ~ Constructor`

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

### *anything...* `handler(effect, cont)`

An effect handler is a function of two parameters, an effect and an effect continuation. If you want to handle an effect, then you do so within this function body
and should return any results of the effect's computation so that they can be fed back
to the requestee. You may also use the `cont` callback to respond instead of returning,
but if you want to respond asynchronously you must return the `wait` sentinel value.
If this function returns nothing then effect resolution is passed on to an outer coroutine.

#### Examples of asynchronous effect handling

##### Version 1: with callbacks and cake.wait

Here cake and copas are completely isolated from eachother and you can not call
copas functions from within the `main()` program. We have much more control over
how and when we respond to an effect.

```lua
local cake = require"cake"
local copas = require"copas"
local asynchttp = require"copas.http"

local effects =
    cake.effects{
        HttpRequest = {get = true}
    }

local function effectful()
    local content = coroutine.yield(effects.HttpRequest.get"https://example.com")
    return content:match("[^\n]+")
end


-- the copas thread that performs the async request.
local function request_async(callback, url)
    local res = assert(asynchttp.request(url))
    callback(res)
end


--our effect handler
local function handler(effect, cont)
    if effect ~ effects.HttpRequest.get then
        copas.addthread(request_async, cont, effect:args())
        return cake.wait -- we **must** tell cake we're handling the effect eventually
                         -- otherwise it would continue up the coroutine chain.
    end
end


local function main()
    local length = cake.run(handler, effectful)
    print("finished:", length)
end


coroutine.wrap(main)() -- because we want to "wait" for copas; our effectful code must
                       -- be ran inside a coroutine so that cake.run can hand off control
                       -- to the copas callback.

copas() -- we start the copas scheduler; note that our effecful code is already waiting for
        -- the http effect to be handled at this point.
```

Here we wrap cake's code in copas completely, which is possible due to
how both libraries tag their yields. The caveat here is that you could use copas within your effectful code
which is not always desirable.

```lua
local effects =
    cake.effects{
        HttpRequest = {get = true}
    }

local function effectful()
    local content = coroutine.yield(effects.HttpRequest.get"https://example.com")
    return content:match"[^\n]+"
end


local function handler(effect)
    if effect ~ effects.HttpRequest.get then
        return assert(asynchttp.request(effect:args()))
    end
end

local function main()
    local length = cake.run(handler, effectful)
    print("finished:", length)
end

copas.addthread(main)

copas()
```

### Examples

```lua
-- A simple logger
local cake = require"cake"

local Log =
    cake.effects {
        Info = true,
        Error = true
    }

function Log.impl(effect)
    if effect ~ Log.Info then
        print("[INFO] "..string.format(effect:args()))
        return true
    elseif effect ~ Log.Error then
        print("[ ERR] "..string.format(effect:args()))
        return true
    end
end

function Log.info(...) return coroutine.yield(Log.Info(...)) end
function Log.error(...) return coroutine.yield(Log.Error(...)) end

run(Log.impl, function()
    for i = 1, 5 do
        Log.info("iteration %i", i)
    end
end)

```

