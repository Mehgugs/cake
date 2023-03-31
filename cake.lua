
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

local function effects(t) return effects_(t, "") end


local runner

local function continue_to_run(self, ...)
    local mask, co, results = table.unpack(self)
    local res = {...}
    if res[1] then
        self.called = {runner(mask, co, table.unpack(res))}
    else
        self.called = {runner(mask, co, coroutine.yield(table.unpack(results, 2)))}
    end
    if self.yielded then
        local success, errr = coroutine.resume(self.yielded)
        if not success then
            error(errr)
        end
    end
end

local cont_mt = {__call = continue_to_run}

local async = {}

function runner(mask, co, ...)
    local results = {coroutine.resume(co, ...)}
    if results[1] then
        local mt = getmetatable(results[2])
        if mt and mt.__cake_effect then
            local cont = setmetatable({mask, co, results}, cont_mt)
            local results2 = {mask(results[2], cont)}

            if not cont.called then
                if results2[1] == nil then
                    return runner(mask, co, coroutine.yield(table.unpack(results, 2)))
                elseif results2[1] == async and not cont.yielded then
                    cont.yielded = coroutine.running()
                    coroutine.yield()
                    assert(cont.called)
                    return table.unpack(cont.called)
                else
                    return runner(mask, co, table.unpack(results2))
                end
            elseif cont.called then
                return table.unpack(cont.called)
            end
        else
            return table.unpack(results, 2)
        end
    else
        error(results[2])
    end
end

local function run(mask, f, ...)
    return runner(mask, coroutine.create(f), ...)
end

return {run = run, effects = effects, wait = async}