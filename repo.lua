--!strict
--!native

local BASE = "https://raw.githubusercontent.com/xexxnx18-prog/QuickTools/refs/heads/main/"

local cache: {[string]: any} = {}

local function repo(name: string)
    if cache[name] ~= nil then
        return cache[name]
    end

    local src = game:HttpGet(BASE .. name .. ".lua")
    local mod = loadstring(src)()
    cache[name] = mod
    return mod
end

return repo
