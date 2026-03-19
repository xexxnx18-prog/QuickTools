--!strict
--!native
-- Made it By xnx and ChatGPT 
-- Probably This Dex Lite I'm not sure...
local IF = {}
IF.Version = "1.3.0.7.2-debug"

local function warnf(msg)
	warn("[!] "..msg)
end

local function printf(msg)
	print("[*] "..msg)
end

local getactors = getactors or function()
	warnf("getactors missing → actor watching disabled")
	return {}
end

local run_on_actor = run_on_actor or function(_, fn, ...)
	warnf("run_on_actor missing → actor bridge disabled")
	return fn(...)
end

local Services = setmetatable({}, {
	__index = function(self, k)
		local ok, s = pcall(game.GetService, game, k)
		if not ok or not s then
			warnf("Service '"..tostring(k).."' unavailable → services may work incorrectly")
			return nil
		end
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

if not S.workspace then warnf("Workspace missing") end
if not S.players then warnf("Players missing") end

local WorkspaceRoot: Workspace = S.workspace

local motion = setmetatable({}, { __mode = "k" })
local eventmap = setmetatable({}, { __mode = "k" })

local function isactor(o: Instance)
	return o:IsA("Actor")
end

local function StepHRP(hrp: BasePart, now: number)
	local s = motion[hrp]
	if not s then
		motion[hrp] = { p = hrp.Position, v = Vector3.zero, a = Vector3.zero, t = now }
		return motion[hrp]
	end
	local dt = now - s.t
	if dt <= 0 then
		warnf("Zero / negative dt detected on HRP")
		return s
	end
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
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		warnf("Character missing HumanoidRootPart")
	end
	return hrp
end

local function Describe(o: Instance)
	if not o or not o.Parent then
		warnf("Describe called on destroyed instance")
	end
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

local function Depth(o: Instance, root: Instance?)
	if not root then
		warnf("Depth check without root")
		return 0
	end
	if o == root then return 0 end
	local d = 0
	local cur = o
	while cur and cur ~= root do
		cur = cur.Parent
		if cur then d += 1 end
	end
	if cur ~= root then
		warnf("Depth overflow → object escaped root tree")
		return math.huge
	end
	return d
end

local function GetTeam(o: Instance)
	if not S.players then
		warnf("Players service missing → team filters disabled")
		return nil
	end
	local char = GetCharacter(o)
	if not char then return nil end
	local p = S.players:GetPlayerFromCharacter(char)
	return p and p.Team and p.Team.Name or nil
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
		if typeof(key) == "Instance" then
			local m = eventmap[key]
			if not m then
				m = {}
				eventmap[key] = m
			end
			m[ev] = (m[ev] or 0) + 1
			if isactor(key) then
				run_on_actor(key :: Actor, function(e)
					if script and script.SetAttribute then
						script:SetAttribute("__if_event", e)
					else
						warnf("script.SetAttribute unavailable inside actor")
					end
				end, ev)
			end
		end
	end

	local ok, err = pcall(cb, ev, payload)
	if not ok then
		warnf("Callback error on event '"..ev.."': "..tostring(err))
	end
end

local function Watch(o: Instance, cb, bag, seen, run, opt, root: Instance, stats)
	if seen[o] then return end
	if opt.Ignore and opt.Ignore[o] then return end
	if opt.Root and not o:IsDescendantOf(root) and o ~= root then return end

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

	cons[#cons+1] = o.AttributeChanged:Connect(function()
		if alive and run[1] then
			Fire(cb, opt.EventMask, "attr", { self = Describe(o) }, stamp, opt.Debounce)
		end
	end)

	cons[#cons+1] = o.ChildAdded:Connect(function(c)
		if alive and run[1] then
			Fire(cb, opt.EventMask, "child", { self = Describe(o), child = Describe(c) }, stamp, opt.Debounce)
		end
	end)

	cons[#cons+1] = o.Destroying:Connect(function()
		if not alive then return end
		alive = false
		stats.destroyed += 1
		Fire(cb, opt.EventMask, "destroy", { self = Describe(o) }, stamp)
		eventmap[o] = nil
		for _,c in ipairs(cons) do c:Disconnect() end
		bag[o] = nil
		seen[o] = nil
	end)

	bag[o] = cons
end

function IF.Start(cb, opt)
	opt = opt or {}
	opt.EventMask = opt.EventMask or {
		init=true, ancestry=true, parent=true,
		child=true, attr=true, destroy=true
	}

	if typeof(cb) ~= "function" then
		error("[!] Start(cb) requires function callback")
	end

	local root: Instance = opt.Root or WorkspaceRoot
	if not root then
		warnf("Root missing → watcher will not start")
	end

	local bag = {}
	local seen = setmetatable({}, { __mode = "k" })
	local run = { true }
	local stats = { watched = 0, destroyed = 0 }

	printf("IF started | version "..IF.Version)

	local function Rescan()
		table.clear(seen)
		Watch(root, cb, bag, seen, run, opt, root, stats)
		for _,v in ipairs(root:GetDescendants()) do
			if opt.Throttle then task.wait(opt.Throttle) end
			Watch(v, cb, bag, seen, run, opt, root, stats)
		end
	end

	Rescan()

	local added = root.DescendantAdded:Connect(function(v)
		if opt.Throttle then task.wait(opt.Throttle) end
		Watch(v, cb, bag, seen, run, opt, root, stats)
	end)

	return {
		Stop = function()
			if not run[1] then return end
			run[1] = false
			added:Disconnect()
			for _,cons in pairs(bag) do
				for _,c in ipairs(cons) do c:Disconnect() end
			end
			table.clear(bag)
			table.clear(seen)
			table.clear(eventmap)
			printf("IF stopped")
		end,
		Stats = function()
			return stats
		end,
		Map = function()
			return eventmap
		end
	}
end

return IF
