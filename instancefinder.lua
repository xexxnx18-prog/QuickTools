--!strict
--!native

local IF = {}
IF.Version = "1.2.1 BETA"

local task = task
local WorkspaceRoot: Workspace = workspace

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

local function Pass(o: Instance, opt, root: Instance): boolean
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
    if not run[1] or seen[o] or not Pass(o, opt, root) then return end
    seen[o] = true

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
            Fire(cb, opt.EventMask, "child", {
                self = Describe(o),
                child = Describe(c)
            })
        end
        task.defer(Watch, c, cb, bag, seen, run, opt, root)
    end)

    if o.GetAttributes then
        local hooked = {}
        for k in pairs(o:GetAttributes()) do
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
        cons[#cons+1] = o.AttributeChanged:Connect(function(k)
            if not hooked[k] then
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
        end)
    end

    o.Destroying:Once(function()
        if not alive then return end
        alive = false
        if run[1] then
            Fire(cb, opt.EventMask, "destroy", { self = Describe(o) })
        end
        for _,c in cons do c:Disconnect() end
        bag[o] = nil
        seen[o] = nil
    end)

    bag[o] = cons
end

function IF.Start(cb, opt)
    opt = opt or {}
    local root: Instance = opt.Root or WorkspaceRoot

    local bag = {}
    local seen = setmetatable({}, { __mode = "k" })
    local run = { true }

    task.defer(Watch, root, cb, bag, seen, run, opt, root)

    for _,v in root:GetDescendants() do
        if opt.Throttle then task.wait(opt.Throttle) end
        task.defer(Watch, v, cb, bag, seen, run, opt, root)
    end

    local added = root.DescendantAdded:Connect(function(v: Instance)
        if not run[1] then return end
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
            run[1] = true
        end
    }
end

return IF
