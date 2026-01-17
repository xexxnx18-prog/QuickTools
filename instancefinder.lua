--!strict
--!native

local IF = {}
IF.Version = "1.2.5.3 DEV"

local task = task
local WorkspaceRoot: Workspace = workspace

local getsenv = getsenv
local getscriptbytecode = getscriptbytecode
local setfenv = setfenv
local pcall = pcall
local rawget = rawget
local getmetatable = getmetatable
local typeof = typeof

local function Describe(o: Instance)
    return {
        instance = o,
        class = o.ClassName,
        name = o.Name,
        parent = o.Parent,
        attributes = o.GetAttributes and o:GetAttributes() or nil
    }
end

local function Depth(o: Instance, root: Instance): number
    local d = 0
    local cur: Instance? = o
    while cur and cur ~= root do
        d += 1
        cur = cur.Parent
    end
    return d
end

local function AD(o: Instance)
    local ok, env = pcall(function()
        return getsenv and getsenv(o)
    end)

    if ok and typeof(env) == "table" then
        local mt = getmetatable(env)
        if typeof(mt) == "table" then
            local idx = rawget(mt, "__index")
            if idx ~= nil then
                mt.__index = idx
            end
        end
        if setfenv then
            pcall(setfenv, 0, env)
        end
        return true
    end

    if getscriptbytecode then
        pcall(getscriptbytecode, o)
        return true
    end

    return false
end

local function Pass(o: Instance, opt, root: Instance): boolean
    if opt.Ignore and opt.Ignore[o] then return false end
    if opt.Scope == "Workspace" and not o:IsDescendantOf(WorkspaceRoot) then return false end
    if opt.Root and o ~= root and not o:IsDescendantOf(root) then return false end
    if opt.MaxDepth and Depth(o, root) > opt.MaxDepth then return false end
    if opt.Classes and not opt.Classes[o.ClassName] then return false end
    if opt.Names and not opt.Names[o.Name] then return false end
    return true
end

local function Fire(cb, mask, ev, payload)
    if mask and not mask[ev] then return end
    pcall(cb, ev, payload)
end

local function Watch(o: Instance, cb, bag, seen, run, opt, root: Instance)
    if seen[o] or not Pass(o, opt, root) then return end
    seen[o] = true

    if opt.AD and (o:IsA("ModuleScript") or o:IsA("LocalScript")) then
        AD(o)
    end

    local alive = true
    local cons = {}

    Fire(cb, opt.EventMask, "init", { self = Describe(o) })

    cons[#cons+1] = o.AncestryChanged:Connect(function()
        if alive and run[1] then
            Fire(cb, opt.EventMask, "ancestry", { self = Describe(o) })
        end
    end)

    cons[#cons+1] = o:GetPropertyChangedSignal("Parent"):Connect(function()
        if alive and run[1] then
            Fire(cb, opt.EventMask, "parent", { self = Describe(o) })
        end
    end)

    cons[#cons+1] = o.ChildAdded:Connect(function(c: Instance)
        if alive and run[1] then
            Fire(cb, opt.EventMask, "child", { self = Describe(o), child = Describe(c) })
        end
        task.defer(Watch, c, cb, bag, seen, run, opt, root)
    end)

    if o.GetAttributes then
        local hooked = {}
        local function hook(k)
            if hooked[k] then return end
            hooked[k] = true
            cons[#cons+1] = o:GetAttributeChangedSignal(k):Connect(function()
                if alive and run[1] then
                    Fire(cb, opt.EventMask, "attr", {
                        self = Describe(o),
                        key = k,
                        value = o:GetAttribute(k)
                    })
                end
            end)
        end
        for k in pairs(o:GetAttributes()) do hook(k) end
        cons[#cons+1] = o.AttributeChanged:Connect(hook)
    end

    o.Destroying:Once(function()
        if not alive then return end
        alive = false
        Fire(cb, opt.EventMask, "destroy", { self = Describe(o) })
        for _,c in cons do c:Disconnect() end
        bag[o] = nil
        seen[o] = nil
    end)

    bag[o] = cons
end

function IF.Start(cb, opt)
    opt = opt or {}
    opt.EventMask = opt.EventMask or {
        init=true, ancestry=true, parent=true, child=true, attr=true, destroy=true
    }

    local root: Instance = opt.Root or WorkspaceRoot
    local bag = {}
    local seen = setmetatable({}, { __mode = "k" })
    local run = { true }

    local function Rescan()
        task.defer(Watch, root, cb, bag, seen, run, opt, root)
        for _,v in root:GetDescendants() do
            if opt.Throttle then task.wait(opt.Throttle) end
            task.defer(Watch, v, cb, bag, seen, run, opt, root)
        end
    end

    Rescan()

    local added = root.DescendantAdded:Connect(function(v: Instance)
        if opt.Throttle then task.wait(opt.Throttle) end
        task.defer(Watch, v, cb, bag, seen, run, opt, root)
    end)

    return {
        Stop = function()
            if not run[1] then return end
            run[1] = false
            added:Disconnect()
            for _,cons in bag do
                for _,c in cons do c:Disconnect() end
            end
            table.clear(bag)
            table.clear(seen)
        end,
        Pause = function()
            run[1] = false
        end,
        Resume = function()
            if run[1] then return end
            run[1] = true
            Rescan()
        end
    }
end

return IF
