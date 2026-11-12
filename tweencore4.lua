--[[
	tweencore4.lua
	owner: supercaptain1233
	edit: https://github.com/supercaptain1233/tweencore/edit/main/tweencore4.lua
	Delta / mobile / universal
	every module runs on its own 10000 step engine
	20 guard families / 2000 scan angles / 5 scan heights
]]

--=====================================================================
-- 1. SERVICES
--=====================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

--=====================================================================
-- 2. NUMBERS
--=====================================================================
local STEPS = 10000
local GUARDS = 10000
local SLICE = 400
local KINDS = 20
local YAW_COUNT = 2000
local HEIGHTS = 5
local SCAN_RANGE = 75
local TRACER_FROM = Vector2.new(0, 0)

--=====================================================================
-- 3. STATE
--=====================================================================
local Core = {
	on = {
		protection = false,
		camera = false,
		noclip = false,
		box = false,
		circle = false,
		tracer = false,
		health = false,
		radar = false,
		freeze = false,
		speed = false,
		fly = false,
		bright = false,
	},
	esp = {},
	conns = {},
	cursor = 0,
	frame = 0,
	tweenToken = 0,
	freezeUntil = 0,
	freezeCF = nil,
	speed = 16,
	flySpeed = 70,
	flyBV = nil,
	lastPos = nil,
	autoFreeze = true,
	err = "ok",
	followOffset = CFrame.new(0, 4.5, 11),
	radar = { cursor = 0, dist = {}, bestYaw = nil, bestWidth = 0, scans = 0 },
	saved = { ambient = nil, brightness = nil, outdoor = nil },
}

local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		Core.err = tostring(err)
	end
	return ok
end

local function getChar()
	local c = LP.Character
	if not c then
		return nil, nil, nil
	end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then
		return nil, nil, nil
	end
	return c, hrp, hum
end

local function clearList(t)
	for i = #t, 1, -1 do
		t[i] = nil
	end
end

--=====================================================================
-- 4. CAMERA ENGINE - 10000 locked frames, plays in order, cannot tangle
--=====================================================================
local function scriptCamera()
	safe(function()
		Camera.CameraType = Enum.CameraType.Scriptable
	end)
end

local function followStep()
	if not Core.on.camera then
		return
	end
	local _, hrp = getChar()
	if not hrp then
		return
	end
	scriptCamera()
	local want = hrp.CFrame * Core.followOffset
	safe(function()
		Camera.CFrame = Camera.CFrame:Lerp(want, 0.1)
	end)
end

local function tweenTo(target, seconds)
	seconds = math.max(seconds or 1, 0.2)
	scriptCamera()
	local startCF = Camera.CFrame
	local frames = table.create(STEPS)
	for s = 1, STEPS do
		local a = (s - 1) / (STEPS - 1)
		local e = a * a * (3 - 2 * a)
		frames[s] = startCF:Lerp(target, e)
	end
	Core.tweenToken = Core.tweenToken + 1
	local token = Core.tweenToken
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if Core.tweenToken ~= token then
			if conn then
				conn:Disconnect()
			end
			return
		end
		local a = (os.clock() - t0) / seconds
		local idx = math.clamp(math.floor(a * (STEPS - 1)) + 1, 1, STEPS)
		safe(function()
			Camera.CFrame = frames[idx]
		end)
		if a >= 1 then
			conn:Disconnect()
			Core.on.camera = true
		end
	end)
	table.insert(Core.conns, conn)
end

local function nearestTarget()
	local _, hrp = getChar()
	if not hrp then
		return nil
	end
	local best, bestD
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and p.Character then
			local h = p.Character:FindFirstChild("HumanoidRootPart")
			if h then
				local d = (h.Position - hrp.Position).Magnitude
				if not bestD or d < bestD then
					best = h
					bestD = d
				end
			end
		end
	end
	return best, bestD, hrp
end

local function doTween()
	local best, bestD, hrp = nearestTarget()
	if not hrp then
		return
	end
	local target
	if best and bestD and bestD > 1 then
		local away = (hrp.Position - best.Position).Unit
		target = CFrame.lookAt(best.Position + away * 13 + Vector3.new(0, 6, 0), best.Position + Vector3.new(0, 2, 0))
	else
		local fwd = hrp.CFrame.LookVector
		target = CFrame.lookAt(hrp.Position + fwd * 15 + Vector3.new(0, 6, 0), hrp.Position + fwd * 45)
	end
	tweenTo(target, 1)
end

local function releaseCamera()
	Core.on.camera = false
	Core.tweenToken = Core.tweenToken + 1
	safe(function()
		Camera.CameraType = Enum.CameraType.Custom
	end)
end

--=====================================================================
-- 5. FREEZE ENGINE - the anti reset
--=====================================================================
local function freezeStep()
	if not Core.on.freeze then
		return
	end
	local _, hrp = getChar()
	if os.clock() >= Core.freezeUntil then
		Core.on.freeze = false
		Core.freezeCF = nil
		if hrp then
			safe(function()
				hrp.Anchored = false
			end)
		end
		return
	end
	if hrp and Core.freezeCF then
		safe(function()
			hrp.CFrame = Core.freezeCF
			hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		end)
	end
end

local function freezeFor(seconds)
	local _, hrp = getChar()
	if not hrp then
		return
	end
	Core.freezeCF = hrp.CFrame
	Core.freezeUntil = os.clock() + math.max(seconds or 2, 0.1)
	Core.on.freeze = true
	safe(function()
		hrp.Anchored = true
	end)
end

--=====================================================================
-- 6. RADAR ENGINE - 10000 rays, 2000 angles, 5 heights
--=====================================================================
local scanParams = RaycastParams.new()
scanParams.FilterType = Enum.RaycastFilterType.Exclude
scanParams.FilterDescendantsInstances = {}

local function radarHop()
	local yaw = Core.radar.bestYaw
	local width = Core.radar.bestWidth
	Core.radar.bestYaw = nil
	Core.radar.dist = {}
	if not yaw or width < 6 then
		return
	end
	local _, hrp = getChar()
	if not hrp then
		return
	end
	local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
	local dest = hrp.Position + dir * math.min(width * 0.6, 15)
	local cf = CFrame.lookAt(dest, dest + dir)
	safe(function()
		hrp.CFrame = cf
		hrp.Anchored = true
	end)
	Core.freezeCF = cf
	Core.freezeUntil = os.clock() + 0.3
	Core.on.freeze = true
end

local function radarScanSlice()
	if not Core.on.radar then
		return
	end
	local c, hrp = getChar()
	if not hrp then
		return
	end
	scanParams.FilterDescendantsInstances = { c }
	local origin = hrp.Position
	for _ = 1, 300 do
		Core.radar.cursor = Core.radar.cursor + 1
		if Core.radar.cursor > STEPS then
			break
		end
		local i = Core.radar.cursor
		local yawIdx = (i - 1) % YAW_COUNT
		local hIdx = math.floor((i - 1) / YAW_COUNT)
		local yaw = (yawIdx / YAW_COUNT) * math.pi * 2
		local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
		local up = -1.3 + hIdx * 1.15
		local hit = Workspace:Raycast(origin + Vector3.new(0, up, 0), dir * SCAN_RANGE, scanParams)
		local d = hit and hit.Distance or SCAN_RANGE
		local old = Core.radar.dist[yawIdx]
		if not old or d < old then
			Core.radar.dist[yawIdx] = d
		end
	end
	if Core.radar.cursor >= STEPS then
		Core.radar.cursor = 0
		Core.radar.scans = Core.radar.scans + 1
		local key, val = nil, 0
		for k, v in pairs(Core.radar.dist) do
			if v > val then
				key = k
				val = v
			end
		end
		Core.radar.bestYaw = key and (key / YAW_COUNT) * math.pi * 2 or nil
		Core.radar.bestWidth = val
		radarHop()
	end
end

--=====================================================================
-- 7. ESP ENGINE - box, circle, tracer, health
--=====================================================================
local function hideESP(e)
	e.box.Visible = false
	e.circle.Visible = false
	e.label.Visible = false
	e.tracer.Visible = false
end

local function updateOneESP(plr)
	local e = Core.esp[plr]
	if not e then
		return
	end
	local c = plr.Character
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	local head = c and c:FindFirstChild("Head")
	if not hrp or not head then
		hideESP(e)
		return
	end
	local dist = (Camera.CFrame.Position - hrp.Position).Magnitude
	if dist > 1500 then
		hideESP(e)
		return
	end
	local pos, onScreen = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 1.2, 0))
	if not onScreen then
		hideESP(e)
		return
	end
	local h = math.clamp(2600 / math.max(dist, 3), 26, 430)
	local w = h * 0.62
	e.box.Visible = Core.on.box or Core.on.health
	e.box.Size = UDim2.fromOffset(w, h)
	e.box.Position = UDim2.fromOffset(pos.X - w * 0.5, pos.Y - h)
	e.circle.Visible = Core.on.circle
	e.circle.Size = UDim2.fromOffset(w * 1.2, w * 1.2)
	e.circle.Position = UDim2.fromOffset(pos.X - w * 0.6, pos.Y - h * 0.55)
	e.label.Visible = Core.on.box or Core.on.circle or Core.on.health
	e.label.Text = string.format("%s  %d", plr.Name, math.floor(dist))
	e.label.Position = UDim2.fromOffset(pos.X - 70, pos.Y - h - 18)
	local hum = c:FindFirstChildOfClass("Humanoid")
	if hum and Core.on.health then
		e.bar.Visible = true
		e.bar.Size = UDim2.new(math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1), 0, 0, 3)
		e.bar.BackgroundColor3 = Color3.fromRGB(255 - 255 * (hum.Health / math.max(hum.MaxHealth, 1)), 255 * (hum.Health / math.max(hum.MaxHealth, 1)), 60)
	else
		e.bar.Visible = false
	end
	if Core.on.tracer then
		local from = Vector2.new(Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y)
		local delta = Vector2.new(pos.X, pos.Y) - from
		e.tracer.Visible = true
		e.tracer.Position = UDim2.fromOffset(from.X, from.Y)
		e.tracer.Size = UDim2.fromOffset(delta.Magnitude, 1)
		e.tracer.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	else
		e.tracer.Visible = false
	end
end

local function espStrengthPass()
	local list = Players:GetPlayers()
	local n = #list
	if n == 0 then
		return
	end
	for i = 1, STEPS do
		local p = list[((i - 1) % n) + 1]
		if p ~= LP then
			safe(updateOneESP, p)
		end
	end
end

local function espTick()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP then
			safe(updateOneESP, p)
		end
	end
end

--=====================================================================
-- 8. SPEED + FLY
--=====================================================================
local function speedStep()
	if not Core.on.speed then
		return
	end
	local _, _, hum = getChar()
	if hum and hum.WalkSpeed ~= Core.speed then
		hum.WalkSpeed = Core.speed
	end
end

local function flyStep()
	if not Core.on.fly then
		if Core.flyBV then
			Core.flyBV:Destroy()
			Core.flyBV = nil
		end
		return
	end
	local _, hrp, hum = getChar()
	if not hrp or not hum then
		return
	end
	if not Core.flyBV or Core.flyBV.Parent ~= hrp then
		if Core.flyBV then
			safe(function()
				Core.flyBV:Destroy()
			end)
		end
		local bv = Instance.new("BodyVelocity")
		bv.Name = "tweencoreFly"
		bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bv.Velocity = Vector3.new(0, 0, 0)
		bv.Parent = hrp
		Core.flyBV = bv
		safe(function()
			hum.PlatformStand = true
		end)
	end
	local md = hum.MoveDirection
	if md.Magnitude > 0.05 then
		Core.flyBV.Velocity = md * Core.flySpeed
	else
		Core.flyBV.Velocity = Vector3.new(0, 0, 0)
	end
end

local function stopFly()
	Core.on.fly = false
	if Core.flyBV then
		safe(function()
			Core.flyBV:Destroy()
		end)
		Core.flyBV = nil
	end
	local _, _, hum = getChar()
	if hum then
		safe(function()
			hum.PlatformStand = false
		end)
	end
end

--=====================================================================
-- 9. FULLBRIGHT
--=====================================================================
local function brightOn()
	Core.saved.ambient = Lighting.Ambient
	Core.saved.brightness = Lighting.Brightness
	Core.saved.outdoor = Lighting.OutdoorAmbient
	Lighting.Ambient = Color3.fromRGB(180, 180, 180)
	Lighting.OutdoorAmbient = Color3.fromRGB(180, 180, 180)
	Lighting.Brightness = 3
	Core.on.bright = true
end

local function brightOff()
	Lighting.Ambient = Core.saved.ambient or Color3.fromRGB(70, 70, 70)
	Lighting.OutdoorAmbient = Core.saved.outdoor or Color3.fromRGB(128, 128, 128)
	Lighting.Brightness = Core.saved.brightness or 2
	Core.on.bright = false
end

--=====================================================================
-- 10. PROTECTION - 10000 guards, 20 families, 400 per frame
--=====================================================================
local function noclipWrite(i)
	if not Core.on.noclip then
		return
	end
	local c = LP.Character
	if not c then
		return
	end
	local parts = c:GetDescendants()
	local n = #parts
	if n == 0 then
		return
	end
	local p = parts[((i * 7) % n) + 1]
	if p and p:IsA("BasePart") then
		p.CanCollide = false
	end
end

local function runGuard(i)
	local kind = (i % KINDS) + 1
	if kind == 1 then
		noclipWrite(i)
	elseif kind == 2 then
		freezeStep()
	elseif kind == 3 then
		if Core.on.freeze and os.clock() >= Core.freezeUntil then
			freezeStep()
		end
	elseif kind == 4 then
		followStep()
	elseif kind == 5 then
		speedStep()
	elseif kind == 6 then
		if (Core.on.box or Core.on.circle or Core.on.tracer or Core.on.health) and Core.frame % 10 == 0 then
			espStrengthPass()
		end
	elseif kind == 7 then
		radarScanSlice()
	elseif kind == 8 then
		if Workspace.CurrentCamera ~= Camera then
			Camera = Workspace.CurrentCamera
		end
	elseif kind == 9 then
		if #Core.conns > 120 then
			table.remove(Core.conns, 1)
		end
	elseif kind == 10 then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LP and not Core.esp[p] then
				Core.esp[p] = nil
			end
		end
	elseif kind == 11 then
		flyStep()
	elseif kind == 12 then
		if Core.on.bright and Lighting.Brightness ~= 3 then
			Lighting.Brightness = 3
		end
	elseif kind == 13 then
		if Core.on.freeze and Core.freezeCF then
			local _, hrp = getChar()
			if hrp then
				hrp.CFrame = Core.freezeCF
			end
		end
	elseif kind == 14 then
		if Core.on.camera then
			scriptCamera()
		end
	elseif kind == 15 then
		if Core.err ~= "ok" and #Core.err > 90 then
			Core.err = "ok"
		end
	elseif kind == 16 then
		local _, _, hum = getChar()
		if hum and Core.on.fly and hum.PlatformStand ~= true then
			hum.PlatformStand = true
		end
	elseif kind == 17 then
		if Core.on.noclip then
			local c = LP.Character
			if c then
				local hrp = c:FindFirstChild("HumanoidRootPart")
				if hrp and hrp.CanCollide then
					hrp.CanCollide = false
				end
			end
		end
	elseif kind == 18 then
		if Core.on.radar and #Core.radar.dist > 5000 then
			Core.radar.dist = {}
			Core.radar.cursor = 0
		end
	elseif kind == 19 then
		if Core.on.speed then
			local _, _, hum = getChar()
			if hum and hum.JumpPower and hum.JumpPower < 50 then
				hum.JumpPower = 50
			end
		end
	else
		if Core.on.protection then
			Core.frame = Core.frame + 1
		end
	end
end

local function protectionBeat()
	if not Core.on.protection then
		return
	end
	for _ = 1, SLICE do
		Core.cursor = (Core.cursor % GUARDS) + 1
		safe(runGuard, Core.cursor)
	end
end

--=====================================================================
-- 11. INTERFACE
--=====================================================================
local parentGui = LP:FindFirstChildOfClass("PlayerGui")
if gethui then
	local ok, h = pcall(gethui)
	if ok and h then
		parentGui = h
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "tweencore4"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = parentGui

local root = Instance.new("Frame")
root.Size = UDim2.fromOffset(220, 460)
root.Position = UDim2.new(0, 12, 0.5, -230)
root.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
root.BorderSizePixel = 0
root.Active = true
root.Parent = gui
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 12)
local rs = Instance.new("UIStroke", root)
rs.Color = Color3.fromRGB(0, 225, 150)
rs.Thickness = 1

local head = Instance.new("Frame")
head.Size = UDim2.new(1, 0, 0, 34)
head.BackgroundTransparency = 1
head.Parent = root

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -70, 1, 0)
title.Position = UDim2.fromOffset(12, 0)
title.BackgroundTransparency = 1
title.Text = "tweencore4  x10000"
title.TextColor3 = Color3.fromRGB(0, 235, 155)
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = head

local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(26, 22)
mini.Position = UDim2.new(1, -32, 0, 6)
mini.BackgroundColor3 = Color3.fromRGB(30, 34, 44)
mini.BorderSizePixel = 0
mini.Text = "-"
mini.TextColor3 = Color3.fromRGB(235, 240, 245)
mini.Font = Enum.Font.GothamBold
mini.TextSize = 14
mini.Parent = head
Instance.new("UICorner", mini).CornerRadius = UDim.new(0, 6)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -16, 1, -80)
scroll.Position = UDim2.fromOffset(8, 38)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = root
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

local order = 0
local function mkButton(text)
	order = order + 1
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 36)
	b.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = Color3.fromRGB(233, 238, 244)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.LayoutOrder = order
	b.Parent = scroll
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	return b
end

local function mkSection(text)
	order = order + 1
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 18)
	l.BackgroundTransparency = 1
	l.Text = "  " .. text
	l.TextColor3 = Color3.fromRGB(110, 160, 145)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 10
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.LayoutOrder = order
	l.Parent = scroll
	return l
end

local function paint(b, on)
	b.BackgroundColor3 = on and Color3.fromRGB(0, 140, 92) or Color3.fromRGB(28, 32, 42)
end

mkSection("CORE")
local bProt = mkButton("Protection x10000")
local bTween = mkButton("Tween x10000")
local bNoclip = mkButton("Noclip x10000")
mkSection("VISUALS")
local bBox = mkButton("Box x10000")
local bCircle = mkButton("Circle x10000")
local bTracer = mkButton("Tracer x10000")
local bHealth = mkButton("Health x10000")
mkSection("MOVEMENT")
local bRadar = mkButton("Hole Scan x10000")
local bFreeze = mkButton("Freeze 2s")
local bSpeed = mkButton("Speed 16")
local bFly = mkButton("Fly")
mkSection("WORLD")
local bBright = mkButton("Fullbright")
local bStop = mkButton("STOP ALL")

mini.MouseButton1Click:Connect(function()
	scroll.Visible = not scroll.Visible
	root.Size = scroll.Visible and UDim2.fromOffset(220, 460) or UDim2.fromOffset(220, 36)
end)

bProt.MouseButton1Click:Connect(function()
	Core.on.protection = not Core.on.protection
	paint(bProt, Core.on.protection)
end)

bTween.MouseButton1Click:Connect(function()
	doTween()
	paint(bTween, true)
end)

bNoclip.MouseButton1Click:Connect(function()
	Core.on.noclip = not Core.on.noclip
	paint(bNoclip, Core.on.noclip)
end)

bBox.MouseButton1Click:Connect(function()
	Core.on.box = not Core.on.box
	paint(bBox, Core.on.box)
end)

bCircle.MouseButton1Click:Connect(function()
	Core.on.circle = not Core.on.circle
	paint(bCircle, Core.on.circle)
end)

bTracer.MouseButton1Click:Connect(function()
	Core.on.tracer = not Core.on.tracer
	paint(bTracer, Core.on.tracer)
end)

bHealth.MouseButton1Click:Connect(function()
	Core.on.health = not Core.on.health
	paint(bHealth, Core.on.health)
end)

bRadar.MouseButton1Click:Connect(function()
	Core.on.radar = not Core.on.radar
	Core.radar.cursor = 0
	Core.radar.dist = {}
	paint(bRadar, Core.on.radar)
end)

bFreeze.MouseButton1Click:Connect(function()
	freezeFor(2)
end)

local speeds = { 16, 40, 80, 150, 250 }
local speedIdx = 1
bSpeed.MouseButton1Click:Connect(function()
	speedIdx = speedIdx % #speeds + 1
	Core.speed = speeds[speedIdx]
	Core.on.speed = true
	bSpeed.Text = "Speed " .. tostring(Core.speed)
end)

bFly.MouseButton1Click:Connect(function()
	if Core.on.fly then
		stopFly()
	else
		Core.on.fly = true
	end
	paint(bFly, Core.on.fly)
end)

bBright.MouseButton1Click:Connect(function()
	if Core.on.bright then
		brightOff()
	else
		brightOn()
	end
	paint(bBright, Core.on.bright)
end)

bStop.MouseButton1Click:Connect(function()
	for k in pairs(Core.on) do
		Core.on[k] = false
	end
	Core.tweenToken = Core.tweenToken + 1
	local _, hrp = getChar()
	if hrp then
		safe(function()
			hrp.Anchored = false
		end)
	end
	stopFly()
	brightOff()
	safe(function()
		Camera.CameraType = Enum.CameraType.Custom
	end)
	for p, e in pairs(Core.esp) do
		safe(function()
			e.box:Destroy()
			e.circle:Destroy()
			e.label:Destroy()
			e.tracer:Destroy()
		end)
		Core.esp[p] = nil
	end
	paint(bProt, false)
	paint(bTween, false)
	paint(bNoclip, false)
	paint(bBox, false)
	paint(bCircle, false)
	paint(bTracer, false)
	paint(bHealth, false)
	paint(bRadar, false)
	paint(bFly, false)
	paint(bBright, false)
	bSpeed.Text = "Speed 16"
	speedIdx = 1
	Core.speed = 16
end)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 26)
status.Position = UDim2.new(0, 8, 1, -32)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextColor3 = Color3.fromRGB(130, 200, 175)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = "idle"
status.Parent = root

local dragging = false
local dragStart, startPos
head.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = root.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)
UIS.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local d = input.Position - dragStart
		root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end)

--=====================================================================
-- 12. ESP OBJECTS
--=====================================================================
local function makeESP(plr)
	if Core.esp[plr] then
		return
	end
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ZIndex = 4
	box.Visible = false
	box.Parent = gui
	for _, side in ipairs({ "T", "B", "L", "R" }) do
		local line = Instance.new("Frame")
		line.BackgroundColor3 = Color3.fromRGB(0, 255, 140)
		line.BorderSizePixel = 0
		line.ZIndex = 4
		if side == "T" or side == "B" then
			line.Size = UDim2.new(1, 0, 0, 2)
			line.Position = side == "T" and UDim2.new() or UDim2.new(0, 0, 1, -2)
		else
			line.Size = UDim2.new(0, 2, 1, 0)
			line.Position = side == "L" and UDim2.new() or UDim2.new(1, -2, 0, 0)
		end
		line.Parent = box
	end
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 3)
	bar.Position = UDim2.new(0, 0, 1, 4)
	bar.BackgroundColor3 = Color3.fromRGB(0, 255, 90)
	bar.BorderSizePixel = 0
	bar.ZIndex = 5
	bar.Visible = false
	bar.Parent = box
	local circle = Instance.new("Frame")
	circle.BackgroundTransparency = 1
	circle.BorderSizePixel = 0
	circle.ZIndex = 4
	circle.Visible = false
	circle.Parent = gui
	Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)
	local cs = Instance.new("UIStroke", circle)
	cs.Color = Color3.fromRGB(255, 220, 0)
	cs.Thickness = 2
	local tracer = Instance.new("Frame")
	tracer.BackgroundColor3 = Color3.fromRGB(255, 120, 0)
	tracer.BorderSizePixel = 0
	tracer.AnchorPoint = Vector2.new(0, 0.5)
	tracer.ZIndex = 3
	tracer.Visible = false
	tracer.Parent = gui
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(140, 16)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0
	label.ZIndex = 5
	label.Visible = false
	label.Parent = gui
	Core.esp[plr] = { box = box, circle = circle, tracer = tracer, label = label, bar = bar }
end

for _, p in ipairs(Players:GetPlayers()) do
	if p ~= LP then
		makeESP(p)
	end
end
Players.PlayerAdded:Connect(function(p)
	if p ~= LP then
		makeESP(p)
	end
end)
Players.PlayerRemoving:Connect(function(p)
	local e = Core.esp[p]
	if e then
		e.box:Destroy()
		e.circle:Destroy()
		e.tracer:Destroy()
		e.label:Destroy()
		Core.esp[p] = nil
	end
end)

--=====================================================================
-- 13. MAIN LOOP
--=====================================================================
Core.on.protection = true
paint(bProt, true)

local heartbeat = RunService.Heartbeat:Connect(function(dt)
	protectionBeat()
	safe(espTick)
	local _, hrp = getChar()
	if hrp then
		if Core.lastPos and Core.autoFreeze and not Core.on.freeze then
			if (hrp.Position - Core.lastPos).Magnitude > 28 then
				freezeFor(0.6)
			end
		end
		Core.lastPos = hrp.Position
	else
		Core.lastPos = nil
	end
	if Core.on.freeze then
		status.Text = "freezing"
	elseif Core.on.radar then
		status.Text = "scanning " .. tostring(Core.radar.scans)
	elseif Core.err ~= "ok" then
		status.Text = "check"
	else
		status.Text = "running  " .. tostring(math.floor(1 / math.max(dt, 0.001))) .. " fps"
	end
end)
table.insert(Core.conns, heartbeat)

LP.CharacterAdded:Connect(function()
	Core.lastPos = nil
	Core.on.freeze = false
	Core.freezeCF = nil
	Core.flyBV = nil
	Core.radar.dist = {}
	Core.radar.cursor = 0
end)

task.spawn(function()
	while gui.Parent do
		task.wait(0.5)
		if #Core.conns > 120 then
			table.remove(Core.conns, 1)
		end
	end
end)

print("tweencore4 loaded - 10000 engines")
