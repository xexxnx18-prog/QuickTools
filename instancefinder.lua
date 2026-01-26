--!strict
--!native

local IF = {}
IF.Version = "1.3.0.7.1"

local getactors = getactors or function() return {} end
local run_on_actor = run_on_actor or function(_, fn, ...) return fn(...) end

local Services = setmetatable({}, {
	__index = function(self, k)
		local s = game:GetService(k)
		rawset(self, k, s)
		return s
	end
})

local S = {
	task = task,
	clock = os.clock,
	services = Services
}

S.workspace = Services.Workspace
S.players = Services.Players

local WorkspaceRoot: Workspace = S.workspace

local motion = setmetatable({}, { __mode = "k" })
local eventmap = setmetatable({}, { __mode = "k" })

local scriptgraph = setmetatable({}, { __mode = "k" })

local function scriptnode(scr)
	local n = scriptgraph[scr]
	if not n then
		n = { requires = {}, fires = {}, listens = {}, creates = {}, mutates = {} }
		scriptgraph[scr] = n
	end
	return n
end

local function currentscript()
	return getcallingscript()
end

do
	local oldrequire = require
	require = function(m)
		local src = currentscript()
		if src then
			scriptnode(src).requires[m] = true
		end
		return oldrequire(m)
	end
end

do
	local oldnc
	oldnc = hookmetamethod(game, "__namecall", function(self, ...)
		local m = getnamecallmethod()
		local src = currentscript()
		if src and m == "FireServer" and typeof(self) == "Instance" and self:IsA("RemoteEvent") then
			scriptnode(src).fires[self] = true
		end
		return oldnc(self, ...)
	end)
end

do
	local oldconnect
	oldconnect = hookfunction(Instance.new("BindableEvent").Event.Connect, function(sig, fn)
		local src = currentscript()
		if src then
			local up = debug.getupvalue(fn, 1)
			if typeof(up) == "Instance" then
				scriptnode(src).listens[up] = true
			end
		end
		return oldconnect(sig, fn)
	end)
end

do
	local oldnew = Instance.new
	Instance.new = function(class, parent)
		local obj = oldnew(class, parent)
		local src = currentscript()
		if src then
			scriptnode(src).creates[obj] = true
		end
		return obj
	end
end

local function isactor(o: Instance)
	return o:IsA("Actor")
end

local function StepHRP(hrp: BasePart, now: number)
	local s = motion[hrp]
	if not s then
		s = { p = hrp.Position, v = Vector3.zero, a = Vector3.zero, t = now }
		motion[hrp] = s
		return s
	end
	local dt = now - s.t
	if dt <= 0 then return s end
	local pos = hrp.Position
	local vel = (pos - s.p) / dt
	s.a = (vel - s.v) / dt
	s.v = vel
	s.p = pos
	s.t = now
	return s
end

local function GetCharacter(o: Instance)
	local m = o:FindFirstAncestorOfClass("Model")
	if not m then return nil end
	if not m:FindFirstChildOfClass("Humanoid") then return nil end
	return m
end

local function GetHRP(char: Model?)
	return char and char:FindFirstChild("HumanoidRootPart") or nil
end

local function Describe(o: Instance)
	local char = GetCharacter(o)
	local hrp = GetHRP(char)
	local now = S.clock()
	local m = hrp and StepHRP(hrp, now) or nil
	local vel = m and m.v or nil
	return {
		instance = o,
		class = o.ClassName,
		name = o.Name,
		parent = o.Parent,
		character = char,
		hrp = hrp,
		position = hrp and hrp.Position or nil,
		velocity = vel,
		speed = vel and vel.Magnitude or nil,
		accel = m and m.a or nil,
		attributes = o.GetAttributes and o:GetAttributes() or nil
	}
end

local function Depth(o: Instance, root: Instance): number
	if o == root then return 0 end
	local d = 0
	local cur = o
	while cur and cur ~= root do
		cur = cur.Parent
		if cur then d += 1 end
	end
	return cur == root and d or math.huge
end

local function GetTeam(o: Instance)
	local char = GetCharacter(o)
	if not char then return nil end
	local p = S.players:GetPlayerFromCharacter(char)
	return p and p.Team and p.Team.Name or nil
end

local function Pass(o: Instance, opt, root: Instance): boolean
	if opt.Ignore and opt.Ignore[o] then return false end
	if opt.Scope == "Workspace" and not o:IsDescendantOf(WorkspaceRoot) then return false end
	if opt.Root and o ~= root and not o:IsDescendantOf(root) then return false end
	if opt.MaxDepth and Depth(o, root) > opt.MaxDepth then return false end
	if opt.Classes and not opt.Classes[o.ClassName] then return false end
	if opt.Names and not opt.Names[o.Name] then return false end
	if opt.Team or opt.TeamBlacklist then
		local team = GetTeam(o)
		if opt.Team and (not team or not opt.Team[team]) then return false end
		if opt.TeamBlacklist and team and opt.TeamBlacklist[team] then return false end
	end
	return true
end

local function actorbridge(actor: Actor, ev)
	run_on_actor(actor, function(e)
		if script and script.SetAttribute then
			script:SetAttribute("__if_event", e)
		end
	end, ev)
end

local function Fire(cb, mask, ev, payload, stamp, debounce)
	if mask and not mask[ev] then return end
	if debounce then
		local t = S.clock()
		local s = stamp[ev]
		if s and t - s < debounce then return end
		stamp[ev] = t
	end
	local selfd = payload and payload.self
	if selfd then
		local key = selfd.character or selfd.hrp or selfd.instance
		local m = eventmap[key]
		if not m then m = {}; eventmap[key] = m end
		m[ev] = (m[ev] or 0) + 1
		if typeof(key) == "Instance" and isactor(key) then
			actorbridge(key :: Actor, ev)
		end
	end
	pcall(cb, ev, payload)
end

local function Watch(o: Instance, cb, bag, seen, run, opt, root: Instance, stats)
	if seen[o] then return end
	if not Pass(o, opt, root) then return end

	seen[o] = true
	stats.watched += 1

	local alive = true
	local cons = {}
	local stamp = {}

	Fire(cb, opt.EventMask, "init", { self = Describe(o) }, stamp, opt.Debounce)

	cons[#cons+1] = o.AncestryChanged:Connect(function()
		if alive and run[1] then
			Fire(cb, opt.EventMask, "ancestry", { self = Describe(o) }, stamp, opt.Debounce)
		end
	end)

	cons[#cons+1] = o:GetPropertyChangedSignal("Parent"):Connect(function()
		if alive and run[1] then
			Fire(cb, opt.EventMask, "parent", { self = Describe(o) }, stamp, opt.Debounce)
		end
	end)

	cons[#cons+1] = o.ChildAdded:Connect(function(c)
		if alive and run[1] then
			Fire(cb, opt.EventMask, "child", { self = Describe(o), child = Describe(c) }, stamp, opt.Debounce)
		end
		S.task.defer(Watch, c, cb, bag, seen, run, opt, root, stats)
	end)

	if isactor(o) then
		cons[#cons+1] = o.ChildRemoved:Connect(function(c)
			if alive and run[1] then
				Fire(cb, opt.EventMask, "childremove", { self = Describe(o), child = Describe(c) }, stamp, opt.Debounce)
			end
		end)
	end

	cons[#cons+1] = o.Destroying:Connect(function()
		if not alive then return end
		alive = false
		stats.destroyed += 1
		eventmap[o] = nil
		for _,c in cons do c:Disconnect() end
		bag[o] = nil
		seen[o] = nil
	end)

	bag[o] = cons
end

local function WatchActors(cb, bag, seen, run, opt, stats)
	if opt.Actors == false then return end
	for _,actor in getactors() do
		if not seen[actor] then
			S.task.defer(Watch, actor, cb, bag, seen, run, opt, actor, stats)
		end
	end
end

function IF.Start(cb, opt)
	opt = opt or {}
	opt.EventMask = opt.EventMask or {
		init=true, ancestry=true, parent=true,
		child=true, childremove=true,
		attr=true, destroy=true
	}

	local root: Instance = opt.Root or WorkspaceRoot
	local bag = {}
	local seen = setmetatable({}, { __mode = "k" })
	local run = { true }
	local stats = { watched = 0, destroyed = 0 }

	local function Rescan()
		for k in pairs(seen) do seen[k] = nil end
		S.task.defer(Watch, root, cb, bag, seen, run, opt, root, stats)
		for _,v in root:GetDescendants() do
			if opt.Throttle then S.task.wait(opt.Throttle) end
			S.task.defer(Watch, v, cb, bag, seen, run, opt, root, stats)
		end
	end

	Rescan()
	WatchActors(cb, bag, seen, run, opt, stats)

	local added = root.DescendantAdded:Connect(function(v)
		if opt.Throttle then S.task.wait(opt.Throttle) end
		S.task.defer(Watch, v, cb, bag, seen, run, opt, root, stats)
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
			table.clear(eventmap)
		end,
		Pause = function()
			run[1] = false
		end,
		Resume = function()
			if run[1] then return end
			run[1] = true
			Rescan()
			WatchActors(cb, bag, seen, run, opt, stats)
		end,
		Stats = function()
			return stats
		end,
		Map = function()
			return eventmap
		end
	}
end

function IF.PrintTree()
	for scr, node in scriptgraph do
		print("Script:", scr)
		for k in pairs(node.requires) do print("├─ requires:", k) end
		for k in pairs(node.fires) do print("├─ fires:", k) end
		for k in pairs(node.listens) do print("├─ listens:", k) end
		for k in pairs(node.creates) do print("└─ creates:", k) end
		print("")
	end
end

return IF
