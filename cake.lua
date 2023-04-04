
local effect_t = {}

function effect_t:__call(...)
    return setmetatable(table.pack(...), self)
end

local function t__bxor(self, other)
    return getmetatable(self) == other and self
end

local function make_effect(name)
    local t = {__name = name, __cake_effect = true}
    t.__index = {args = table.unpack, name = name}
    t.__bxor = t__bxor
    return setmetatable(t, effect_t)
end

local function ptr_eql(self, other) return self == other and self end
local make_symbol

local function symbols__index(t, k)
    return make_symbol(t.__name .. "."..k, t.__cake_symbols)
end

function make_symbol(name, cache)
    local t = {
        __name = name,
        __cake_effect = true,
        __cake_symbols = cache,
        __index = symbols__index,
        __bxor = ptr_eql
    }


    local out = setmetatable(t, t)
    cache[name] = out

    return out
end

local function symbols_index(self, k)
    return make_symbol(k, self)
end

local symbols = setmetatable({}, {__mode = "v", __index = symbols_index})


local function effects_(t, name)
    local out = {}

    for k, v in pairs(t) do
        if type(v) == "table" then
            out[k] = effects_(v, name == "" and k or (name .. "." .. k))
        else
            out[k] = make_effect(name == "" and k or (name .. "." .. k))
        end
    end
    return out
end

local function effects(t)
    if type(t) == "string" then
        return function(t_) return effects_(t_, t) end
    else
        return effects_(t, "")
    end
end


local function drop1(status, e, ...)
    if status then
        return e, ...
    else
        error(e)
    end
end

local function pack2(f, e, ...)
    if f(e) then
        return e, table.pack(...)
    else
        return false, table.pack(e, ...)
    end
end

local async = {}
local abort = {}


local function is_effect(x)
    local mt = getmetatable(x)
    return mt and mt.__cake_effect
end

local serialized_runner

local function do_cont(self, ...)
    if coroutine.status(self.thread) == "suspended" then
        return drop1(coroutine.resume(self.thread, ...))
    else
        if self[2] then error("coroutine being managed by this continuation has been resumed already") end
        local results = table.pack(serialized_runner(self.mask, self.co, ...))
        self[1] = results
        self[2] = true
        return table.unpack(results)
    end
end

local function do_abort(self, ...)
    if coroutine.status(self.thread[1]) == "suspended" then
        return drop1(coroutine.resume(self.thread[1], abort, ...))
    else
        local pack = table.pack(abort, ...)
        self[1] = pack
        return ...
    end
end

local cont2_mt = {__call = do_cont}
local aborter_mt = {__call = do_abort}
local weak_mt = {__mode = "v"}


local aborter_cache = setmetatable({}, {
    __mode = "k",
    __index = function(self, k)
        local cached = setmetatable({thread = setmetatable({k}, weak_mt)}, aborter_mt)
        self[k] = cached
        return cached
    end
})

local throw = make_effect "__throw"

local function did_abort(x) return x == abort end

local function run_once(mask, co, results)
    local inner_thread
    if getmetatable(results[2]) == throw then
        results[2], inner_thread = results[2]:args()
    end

    local thread = coroutine.running()
    local cont = setmetatable({thread = coroutine.running(), co = co, mask = mask}, cont2_mt)
    local aborter = aborter_cache[thread]
    local handled = table.pack(mask(results[2], cont, aborter))

    if aborter[1] then
        handled = aborter[1]
    elseif cont[2] then
        return 1, cont[1]
    elseif cont[1] then
        handled = cont[1]
    end

    if handled.n == 0 then
        local throweff = throw(results[2], (coroutine.running()))
        local aborted

        aborted, handled = pack2(did_abort, coroutine.yield(throweff))

        if aborted then
            return 1, handled
        end
    elseif handled[1] == abort then
        if inner_thread then
            return -1, inner_thread, handled
        else
            return 2, handled
        end
    elseif handled[1] == async then
        cont[2] = true
        handled = table.pack(coroutine.yield(table.unpack(handled, 2)))
        if handled[1] == abort then
            return 2, handled
        end
    end

    if coroutine.status(co) ~= "dead" then
        results = table.pack(coroutine.resume(co, table.unpack(handled)))
    else
        results = handled
    end

    return 0, results
end

function serialized_runner(mask, co, ...)
    local results = table.pack(coroutine.resume(co, ...))
    if results[1] then
        while is_effect(results[2]) do
            local idx, pack, ex = run_once(mask, co, results)
            if idx == 0 then
                results = pack
            elseif idx == -1 then
                return drop1(coroutine.resume(pack, table.unpack(ex)))
            else
                return table.unpack(pack, idx)
            end
        end
        return table.unpack(results, 2)
    else
        error(results[2])
    end
end

local handler = setmetatable({}, {__mode = "k"})

local function run(mask, f, ...)
    local co = coroutine.create(f)
    handler[co] = mask
    return serialized_runner(mask, co, ...)
end

local function noop() end

local function parent_handler()
    return handler[coroutine.running()] or noop
end


local function perform(f, ...)
    local co = coroutine.create(run)
    return drop1(coroutine.resume(co, handler[coroutine.running()] or noop, f, ...))
end

local function start(handle, f, ...)
    local co = coroutine.create(run)
    return drop1(coroutine.resume(co, handle, f, ...))
end

return
    { run = run
    , effects = effects
    , simple = symbols
    , wait = async
    , parent_handler = parent_handler
    , perform = perform
    , start = start
    , pass = noop
    }