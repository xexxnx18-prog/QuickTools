--!strict
--!native

local IF = {}
IF.Version = "1.3.0.6.8"

local S = {
	task = task,
	workspace = workspace,
	players = game:GetService("Players"),
	clock = os.clock
}

local WorkspaceRoot: Workspace = S.workspace

local motion = setmetatable({}, { __mode = "k" })
local eventmap = setmetatable({}, { __mode = "k" })

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

local function horiz(v: Vector3)
	return Vector3.new(v.X, 0, v.Z)
end

local function yaw(v: Vector3)
	return math.atan2(-v.Z, v.X)
end

local function pitch(v: Vector3)
	local h = math.sqrt(v.X*v.X + v.Z*v.Z)
	return math.atan2(v.Y, h)
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
	local spd = vel and vel.Magnitude or nil
	local dxz = vel and horiz(vel) or nil
	local dxzmag = dxz and dxz.Magnitude or nil
	return {
		instance = o,
		class = o.ClassName,
		name = o.Name,
		parent = o.Parent,
		character = char,
		hrp = hrp,
		position = hrp and hrp.Position or nil,
		velocity = vel,
		speed = spd,
		accel = m and m.a or nil,
		distance = spd,
		horizdistance = dxzmag,
		direction = vel and (spd and spd > 0 and vel.Unit or Vector3.zero) or nil,
		directionxz = dxz and (dxzmag and dxzmag > 0 and dxz.Unit or Vector3.zero) or nil,
		yaw = vel and yaw(vel) or nil,
		pitch = vel and pitch(vel) or nil,
		eta = spd and spd > 0 and (1 / spd) or math.huge,
		lead = hrp and vel and (hrp.Position + vel * 0.12) or nil,
		attributes = o.GetAttributes and o:GetAttributes() or nil
	}
end

local function Depth(o: Instance, root: Instance): number
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

local function Fire(cb, mask, ev, payload, stamp, debounce)
	if mask and not mask[ev] then return end
	if debounce then
		local t = S.clock()
		if stamp[ev] and t - stamp[ev] < debounce then return end
		stamp[ev] = t
	end
	local s = payload and payload.self
	if s then
		local key = s.character or s.hrp or s.instance
		local m = eventmap[key]
		if not m then
			m = {}
			eventmap[key] = m
		end
		m[ev] = (m[ev] or 0) + 1
	end
	pcall(cb, ev, payload)
end

local function Watch(o: Instance, cb, bag, seen, run, opt, root: Instance, stats)
	if seen[o] or not Pass(o, opt, root) then return end
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
	if o.GetAttributes then
		local hooked = {}
		local function hook(k)
			if hooked[k] then return end
			hooked[k] = true
			cons[#cons+1] = o:GetAttributeChangedSignal(k):Connect(function()
				if alive and run[1] then
					Fire(cb, opt.EventMask, "attr", { self = Describe(o), key = k, value = o:GetAttribute(k) }, stamp, opt.Debounce)
				end
			end)
		end
		for k in pairs(o:GetAttributes()) do hook(k) end
		cons[#cons+1] = o.AttributeChanged:Connect(hook)
	end
	cons[#cons+1] = o.Destroying:Connect(function()
		if not alive then return end
		alive = false
		stats.destroyed += 1
		Fire(cb, opt.EventMask, "destroy", { self = Describe(o) })
		for _,c in cons do c:Disconnect() end
		bag[o] = nil
		seen[o] = nil
	end)
	bag[o] = cons
end

function IF.Start(cb, opt)
	opt = opt or {}
	opt.EventMask = opt.EventMask or { init=true, ancestry=true, parent=true, child=true, attr=true, destroy=true }
	local root: Instance = opt.Root or WorkspaceRoot
	local bag = {}
	local seen = setmetatable({}, { __mode = "k" })
	local run = { true }
	local stats = { watched = 0, destroyed = 0 }
	local function Rescan()
		S.task.defer(Watch, root, cb, bag, seen, run, opt, root, stats)
		for _,v in root:GetDescendants() do
			if opt.Throttle then S.task.wait(opt.Throttle) end
			S.task.defer(Watch, v, cb, bag, seen, run, opt, root, stats)
		end
	end
	Rescan()
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
		end,
		Pause = function()
			run[1] = false
		end,
		Resume = function()
			if run[1] then return end
			run[1] = true
			Rescan()
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
