--[[
InstanceFinder.start(callback [, options])

callback(ev, data, a, val)

ev (string):
    "init"      -> instance first detected
    "ancestry"  -> parent / ancestry changed
    "parent"    -> Parent property changed
    "child"     -> child added to instance
    "attr"      -> attribute changed
    "destroy"   -> instance destroyed

data (table):
    data.instance   -> Instance reference
    data.class      -> ClassName
    data.name       -> Name
    data.parent     -> Parent instance
    data.attributes -> Table of attributes (or nil)

a / val (optional):
    ev == "child" -> a = child Instance
    ev == "attr"  -> a = attribute name, val = new value

returns:
    stop() -> disconnects all listeners and stops finder
--]]
local IF={}
IF.version="2.2.2"

local W=workspace

local function describe(o)
    return {
        instance=o,
        class=o.ClassName,
        name=o.Name,
        parent=o.Parent,
        attributes=(o.GetAttributes and o.Parent) and o:GetAttributes() or nil
    }
end

local function watch(o,cb,bag,seen,running)
    if not running[1] then return end
    if seen[o] then return end
    seen[o]=true

    local alive=true
    cb("init",describe(o))

    local cons={}

    cons[#cons+1]=o.AncestryChanged:Connect(function()
        if alive and running[1] then
            cb("ancestry",describe(o))
        end
    end)

    if o.AttributeChanged then
        cons[#cons+1]=o.AttributeChanged:Connect(function(a)
            if alive and running[1] then
                cb("attr",describe(o),a,o:GetAttribute(a))
            end
        end)
    end

    cons[#cons+1]=o:GetPropertyChangedSignal("Parent"):Connect(function()
        if alive and running[1] then
            cb("parent",describe(o))
        end
    end)

    cons[#cons+1]=o.ChildAdded:Connect(function(c)
        if alive and running[1] then
            cb("child",describe(o),c)
        end
    end)

    o.Destroying:Once(function()
        if not alive then return end
        alive=false
        if running[1] then
            cb("destroy",describe(o))
        end
        for _,c in ipairs(cons) do c:Disconnect() end
        bag[o]=nil
        seen[o]=nil
    end)

    bag[o]=cons
end

IF.start=function(cb)
    local bag={}
    local seen=setmetatable({}, {__mode="k"})
    local running={true}

    for _,v in ipairs(W:GetDescendants()) do
        if not running[1] then break end
        watch(v,cb,bag,seen,running)
    end

    local added=W.DescendantAdded:Connect(function(v)
        watch(v,cb,bag,seen,running)
    end)

    return function()
        if not running[1] then return end
        running[1]=false
        added:Disconnect()
        for _,cons in pairs(bag) do
            for _,c in ipairs(cons) do c:Disconnect() end
        end
        bag={}
        seen={}
    end
end

return IF
