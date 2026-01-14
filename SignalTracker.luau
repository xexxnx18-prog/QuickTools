--[[
SignalTracker v1.2.1

API:
    ST.track(instance, callback [, options]) -> stop()
    ST.trackmany(list, callback [, options]) -> stop()
    ST.trackclass(root, className, callback [, options]) -> stop()

callback(instance, signalName, ...)

DESCRIPTION:
    Listens to all RBXScriptSignals on instances.
    Read-only. No hooks. No property changes.

CALLBACK ARGS:
    instance    -> Instance that owns the signal
    signalName  -> Name of the signal (string)
    ...         -> Signal arguments

OPTIONS:
    options.filter(name, instance)
        Return true to allow the signal.

    options.once (boolean)
        Fire once per signal name.

RETURNS:
    stop()
        Disconnects all signal connections.
--]]
local ST={}
ST.version="1.2.1"

local function issignal(v)
    return typeof(v)=="RBXScriptSignal"
end

local function getsignals(o)
    local t={}
    for k,v in pairs(o) do
        if issignal(v) then
            t[#t+1]={k,v}
        end
    end
    return t
end

ST.track=function(o,cb,opt)
    opt=opt or {}
    local cons={}
    local fired={}
    local filter=opt.filter
    local once=opt.once

    for _,s in ipairs(getsignals(o)) do
        local name,signal=s[1],s[2]
        if not filter or filter(name,o) then
            cons[#cons+1]=signal:Connect(function(...)
                if once then
                    if fired[name] then return end
                    fired[name]=true
                end
                cb(o,name,...)
            end)
        end
    end

    return function()
        for _,c in ipairs(cons) do c:Disconnect() end
        cons={}
        fired={}
    end
end

ST.trackmany=function(list,cb,opt)
    local stops={}
    for _,o in ipairs(list) do
        stops[#stops+1]=ST.track(o,cb,opt)
    end
    return function()
        for _,s in ipairs(stops) do s() end
        stops={}
    end
end

ST.trackclass=function(root,class,cb,opt)
    local stops={}
    for _,v in ipairs(root:GetDescendants()) do
        if v.ClassName==class then
            stops[#stops+1]=ST.track(v,cb,opt)
        end
    end
    return function()
        for _,s in ipairs(stops) do s() end
        stops={}
    end
end

return ST
