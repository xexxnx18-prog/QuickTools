--!strict
-- OffsetTracker 1.2 [ BETA ] unified offsets

local getgc = getgc or function() return {} end
local typeof = typeof
local tostring = tostring
local format = string.format
local clock = os.clock
local task = task

type Rec = {
	o: Instance,
	offset: number,
	prop: string,
	get: ()->any,
	set: (any)->(),
	t: number
}

local ptrfn
for _,k in ipairs({
	"getpointer",
	"getaddress",
	"getptr",
	"getmem",
	"getuserdataaddress"
}) do
	local f = rawget(getgenv(), k)
	if type(f) == "function" then
		ptrfn = f
		break
	end
end

local function hex(n:number):string
	return format("0x%X", n)
end

local function hash(s:string):number
	local h = 2166136261
	for i = 1, #s do
		h = (h ~ s:byte(i)) * 16777619 % 2^32
	end
	return h
end

local function baseaddr(v:Instance):number
	if ptrfn then
		local ok,p = pcall(ptrfn, v)
		if ok and type(p) == "number" then
			return p
		end
	end
	local ok,id = pcall(function()
		return v:GetDebugId(0)
	end)
	if ok and type(id) == "string" then
		return hash(id)
	end
	return hash(tostring(v))
end

local lib = {}
lib.version = "1.2-beta"

function lib.new(cfg)
	local classes = cfg.classes or {}
	local props = cfg.props or {}
	local filter = cfg.filter

	local slots = {}
	for i,p in ipairs(props) do
		slots[p] = i * 0x10
	end

	local map:{[number]:Rec} = {}
	local list:{Rec} = {}

	local function scan()
		for _,v in ipairs(getgc(true)) do
			if typeof(v) == "Instance" then
				if not next(classes) or classes[v.ClassName] then
					if not filter or filter(v) then
						local base = baseaddr(v)
						for _,p in ipairs(props) do
							local ok = pcall(function()
								return (v :: any)[p]
							end)
							if ok then
								local off = base + slots[p]
								if not map[off] then
									local r:Rec = {
										o = v,
										offset = off,
										prop = p,
										get = function()
											return (v :: any)[p]
										end,
										set = function(x)
											(v :: any)[p] = x
										end,
										t = clock()
									}
									map[off] = r
									list[#list+1] = r
								else
									map[off].t = clock()
								end
							end
						end
					end
				end
			end
		end
	end

	task.defer(scan)

	task.spawn(function()
		while true do
			local now = clock()
			for k,r in pairs(map) do
				if not r.o.Parent or now - r.t > 2 then
					map[k] = nil
				end
			end
			task.wait(0.25)
		end
	end)

	return {
		version = lib.version,
		list = list,
		map = map,
		rescan = scan,
		hex = hex
	}
end

return lib
