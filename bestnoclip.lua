--[[
	bestnoclip.lua
	owner: supercaptain1233
	edit: https://github.com/supercaptain1233/tweencore/edit/main/bestnoclip.lua
	Delta / mobile / universal
	500 guard noclip, auto armed on load, no button for it
]]

--=====================================================================
-- 1. SERVICES
--=====================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer

--=====================================================================
-- 2. NUMBERS
--=====================================================================
local GUARDS = 500
local SLICE = 40
local KINDS = 12
local PUSH_AFTER = 0.28
local PUSH_STEP = 0.9
local GHOST = 0.55

--=====================================================================
-- 3. STATE
--=====================================================================
local Noclip = {
	on = false,
	cursor = 0,
	frame = 0,
	armed = true,
	parts = {},
	saved = {},
	conns = {},
	stuckT = 0,
	lastPos = nil,
	char = nil,
	err = "ok",
}

local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		Noclip.err = tostring(err)
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
	if not hrp or not hum then
		return nil, nil, nil
	end
	return c, hrp, hum
end

--=====================================================================
-- 4. NOCLIP CORE
--=====================================================================

-- kill collision on one part and remember what it was
local function killPart(p)
	if not p or not p:IsA("BasePart") then
		return
	end
	if p.CanCollide then
		p.CanCollide = false
	end
end

-- start watching a part: kills collision, makes it see through,
-- and puts a listener on it so the game cannot turn collision back on
local function watchPart(p)
	if not p or not p:IsA("BasePart") then
		return
	end
	if Noclip.parts[p] then
		return
	end
	Noclip.parts[p] = true
	Noclip.saved[p] = { col = p.CanCollide, tr = p.Transparency }
	p.CanCollide = false
	safe(function()
		p.Transparency = GHOST
	end)
	local conn = p:GetPropertyChangedSignal("CanCollide"):Connect(function()
		if Noclip.on and p.CanCollide then
			p.CanCollide = false
		end
	end)
	table.insert(Noclip.conns, conn)
end

local function collectAll()
	local c = LP.Character
	if not c then
		return
	end
	for _, d in ipairs(c:GetDescendants()) do
		watchPart(d)
	end
end

local function releaseAll()
	for p in pairs(Noclip.parts) do
		local s = Noclip.saved[p]
		if p and p.Parent and s then
			safe(function()
				p.CanCollide = s.col
				p.Transparency = s.tr
			end)
		end
	end
	Noclip.parts = {}
	Noclip.saved = {}
	for i = #Noclip.conns, 1, -1 do
		safe(function()
			Noclip.conns[i]:Disconnect()
		end)
		Noclip.conns[i] = nil
	end
end

-- the game moved you but you did not actually move: shove forward
local function antiStuck(dt)
	local _, hrp, hum = getChar()
	if not hrp or not hum then
		return
	end
	local md = hum.MoveDirection
	if md.Magnitude < 0.1 then
		Noclip.stuckT = 0
		Noclip.lastPos = hrp.Position
		return
	end
	if not Noclip.lastPos then
		Noclip.lastPos = hrp.Position
		return
	end
	if (hrp.Position - Noclip.lastPos).Magnitude < 0.035 then
		Noclip.stuckT = Noclip.stuckT + dt
	else
		Noclip.stuckT = 0
	end
	Noclip.lastPos = hrp.Position
	if Noclip.stuckT >= PUSH_AFTER then
		Noclip.stuckT = 0
		local dir = Vector3.new(md.X, 0, md.Z)
		if dir.Magnitude > 0.05 then
			dir = dir.Unit
			safe(function()
				hrp.CFrame = hrp.CFrame + dir * PUSH_STEP
			end)
		end
	end
end

--=====================================================================
-- 5. PROTECTION - 500 guards, all noclip, armed on load
--=====================================================================
local function guardKillByIndex(i)
	if not Noclip.on then
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
	local p = parts[((i * 5) % n) + 1]
	if p and p:IsA("BasePart") then
		if p.CanCollide then
			p.CanCollide = false
		end
		if p.Transparency > GHOST + 0.2 then
			p.Transparency = GHOST
		end
	end
end

local function guardGhostByIndex(i)
	if not Noclip.on then
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
	local p = parts[((i * 11) % n) + 1]
	if p and p:IsA("BasePart") and p.Transparency < 0.4 then
		p.Transparency = GHOST
	end
end

local function runGuard(i)
	local kind = (i % KINDS) + 1
	if kind == 1 then
		guardKillByIndex(i)
	elseif kind == 2 then
		guardGhostByIndex(i)
	elseif kind == 3 then
		if Noclip.on then
			local _, hrp = getChar()
			if hrp and hrp.CanCollide then
				hrp.CanCollide = false
			end
		end
	elseif kind == 4 then
		if Noclip.on then
			local _, _, hum = getChar()
			if hum and hum.PlatformStand then
				hum.PlatformStand = false
			end
		end
	elseif kind == 5 then
		if Noclip.on and Noclip.frame % 8 == 0 then
			antiStuck(0.1)
		end
	elseif kind == 6 then
		if Noclip.on and LP.Character and LP.Character ~= Noclip.char then
			Noclip.char = LP.Character
			collectAll()
		end
	elseif kind == 7 then
		if Noclip.on then
			local c = LP.Character
			if c then
				for _, d in ipairs(c:GetChildren()) do
					if d:IsA("BasePart") and not Noclip.parts[d] then
						watchPart(d)
					end
				end
			end
		end
	elseif kind == 8 then
		if Noclip.on then
			local _, _, hum = getChar()
			if hum and hum:GetState() == Enum.HumanoidStateType.Landed then
				hum:ChangeState(Enum.HumanoidStateType.Running)
			end
		end
	elseif kind == 9 then
		if Noclip.on then
			local _, hrp = getChar()
			if hrp then
				for _, d in ipairs(hrp:GetChildren()) do
					if d:IsA("BasePart") and d.CanCollide then
						d.CanCollide = false
					end
				end
			end
		end
	elseif kind == 10 then
		if #Noclip.conns > 400 then
			local old = table.remove(Noclip.conns, 1)
			if old then
				safe(function()
					old:Disconnect()
				end)
			end
		end
	elseif kind == 11 then
		if Noclip.on then
			local _, hrp = getChar()
			if hrp and hrp.Anchored then
				hrp.Anchored = false
			end
		end
	else
		Noclip.frame = Noclip.frame + 1
	end
end

local function protectionBeat()
	if not Noclip.armed then
		return
	end
	for _ = 1, SLICE do
		Noclip.cursor = (Noclip.cursor % GUARDS) + 1
		safe(runGuard, Noclip.cursor)
	end
end

--=====================================================================
-- 6. ON / OFF
--=====================================================================
local function noclipOn()
	if Noclip.on then
		return
	end
	Noclip.on = true
	Noclip.stuckT = 0
	Noclip.lastPos = nil
	Noclip.char = LP.Character
	collectAll()
	local _, _, hum = getChar()
	if hum then
		safe(function()
			hum.PlatformStand = false
		end)
	end
end

local function noclipOff()
	if not Noclip.on then
		return
	end
	Noclip.on = false
	releaseAll()
end

local function toggleNoclip()
	if Noclip.on then
		noclipOff()
	else
		noclipOn()
	end
end

--=====================================================================
-- 7. CHARACTER HOOKS
--=====================================================================
local function hookCharacter(c)
	Noclip.char = c
	c.DescendantAdded:Connect(function(d)
		if Noclip.on and d:IsA("BasePart") then
			watchPart(d)
		end
	end)
	if Noclip.on then
		collectAll()
	end
end

if LP.Character then
	hookCharacter(LP.Character)
end

LP.CharacterAdded:Connect(function(c)
	Noclip.parts = {}
	Noclip.saved = {}
	Noclip.lastPos = nil
	Noclip.stuckT = 0
	task.wait(0.15)
	hookCharacter(c)
end)

--=====================================================================
-- 8. INTERFACE
--=====================================================================
local parentGui = LP:FindFirstChildOfClass("PlayerGui")
if gethui then
	local ok, h = pcall(gethui)
	if ok and h then
		parentGui = h
	end
end

local OPEN_W = UDim2.fromOffset(224, 136)
local DOT_W = UDim2.fromOffset(64, 64)
local R_OPEN = UDim.new(0, 12)
local R_DOT = UDim.new(1, 0)

local gui = Instance.new("ScreenGui")
gui.Name = "bestnoclip"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = parentGui

local root = Instance.new("Frame")
root.Size = OPEN_W
root.Position = UDim2.new(0, 14, 0.5, -68)
root.BackgroundColor3 = Color3.fromRGB(13, 15, 20)
root.BorderSizePixel = 0
root.Active = true
root.ZIndex = 1
root.Parent = gui
local rootCorner = Instance.new("UICorner")
rootCorner.CornerRadius = R_OPEN
rootCorner.Parent = root
local rootStroke = Instance.new("UIStroke")
rootStroke.Color = Color3.fromRGB(0, 235, 150)
rootStroke.Thickness = 1
rootStroke.Parent = root

-- drag layer, only alive while move mode is on
local dragLayer = Instance.new("Frame")
dragLayer.Size = UDim2.fromScale(1, 1)
dragLayer.BackgroundTransparency = 1
dragLayer.BorderSizePixel = 0
dragLayer.Active = true
dragLayer.Visible = false
dragLayer.ZIndex = 4
dragLayer.Parent = root

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 38)
bar.BackgroundTransparency = 1
bar.ZIndex = 3
bar.Parent = root

local title = Instance.new("TextButton")
title.Size = UDim2.fromOffset(132, 30)
title.Position = UDim2.fromOffset(8, 8)
title.BackgroundColor3 = Color3.fromRGB(0, 140, 92)
title.BorderSizePixel = 0
title.Text = "best noclip"
title.TextColor3 = Color3.fromRGB(240, 250, 245)
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.ZIndex = 5
title.Parent = bar
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

local function smallBtn(text, xOffset)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(24, 24)
	b.Position = UDim2.new(1, xOffset, 0, 11)
	b.BackgroundColor3 = Color3.fromRGB(32, 37, 47)
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = Color3.fromRGB(235, 242, 238)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.ZIndex = 5
	b.Parent = bar
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

local moveBtn = smallBtn("✥", -88)
local dotBtn = smallBtn("●", -60)
local closeBtn = smallBtn("✕", -32)

local body = Instance.new("Frame")
body.Size = UDim2.new(1, -16, 0, 82)
body.Position = UDim2.fromOffset(8, 46)
body.BackgroundTransparency = 1
body.ZIndex = 2
body.Parent = root

local noclipBtn = Instance.new("TextButton")
noclipBtn.Size = UDim2.new(1, 0, 0, 54)
noclipBtn.BackgroundColor3 = Color3.fromRGB(30, 36, 46)
noclipBtn.BorderSizePixel = 0
noclipBtn.Text = "NOCLIP"
noclipBtn.TextColor3 = Color3.fromRGB(235, 242, 238)
noclipBtn.Font = Enum.Font.GothamBold
noclipBtn.TextSize = 20
noclipBtn.ZIndex = 3
noclipBtn.Parent = body
Instance.new("UICorner", noclipBtn).CornerRadius = UDim.new(0, 10)
local ncStroke = Instance.new("UIStroke", noclipBtn)
ncStroke.Color = Color3.fromRGB(0, 235, 150)
ncStroke.Thickness = 1

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, 0, 0, 20)
status.Position = UDim2.fromOffset(2, 58)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextColor3 = Color3.fromRGB(120, 200, 170)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = "protection 500 armed"
status.ZIndex = 3
status.Parent = body

-- circle mode button
local dot = Instance.new("TextButton")
dot.Size = UDim2.fromScale(1, 1)
dot.BackgroundColor3 = Color3.fromRGB(0, 140, 92)
dot.BorderSizePixel = 0
dot.Text = "b"
dot.TextColor3 = Color3.fromRGB(240, 250, 245)
dot.Font = Enum.Font.GothamBold
dot.TextSize = 24
dot.ZIndex = 6
dot.Visible = false
dot.Parent = root
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = R_DOT
dotCorner.Parent = dot

--=====================================================================
-- 9. PANEL BEHAVIOUR
--=====================================================================
local dotMode = false
local moveMode = false
local dragging = false
local dragStart = nil
local dragBase = nil
local movedPx = 0

local function paintNoclip()
	if Noclip.on then
		noclipBtn.BackgroundColor3 = Color3.fromRGB(0, 145, 95)
		noclipBtn.Text = "GHOST ON"
		status.Text = "walls off"
	else
		noclipBtn.BackgroundColor3 = Color3.fromRGB(30, 36, 46)
		noclipBtn.Text = "NOCLIP"
		status.Text = "protection 500 armed"
	end
end

noclipBtn.MouseButton1Click:Connect(function()
	toggleNoclip()
	paintNoclip()
end)

local function setDotMode(on)
	dotMode = on
	bar.Visible = not on
	body.Visible = not on
	dot.Visible = on
	dragLayer.Visible = false
	moveMode = false
	root.Size = on and DOT_W or OPEN_W
	rootCorner.CornerRadius = on and R_DOT or R_OPEN
	if on then
		root.BackgroundColor3 = Color3.fromRGB(0, 140, 92)
	else
		root.BackgroundColor3 = Color3.fromRGB(13, 15, 20)
	end
end

dotBtn.MouseButton1Click:Connect(function()
	setDotMode(true)
end)

closeBtn.MouseButton1Click:Connect(function()
	noclipOff()
	gui.Enabled = false
end)

moveBtn.MouseButton1Click:Connect(function()
	moveMode = not moveMode
	dragLayer.Visible = moveMode
	moveBtn.BackgroundColor3 = moveMode and Color3.fromRGB(0, 140, 92) or Color3.fromRGB(32, 37, 47)
end)

local function startDrag(input)
	dragging = true
	movedPx = 0
	dragStart = input.Position
	dragBase = root.Position
end

local function endDrag()
	dragging = false
	if moveMode then
		moveMode = false
		dragLayer.Visible = false
		moveBtn.BackgroundColor3 = Color3.fromRGB(32, 37, 47)
	end
	if dotMode and movedPx < 7 then
		setDotMode(false)
	end
end

dragLayer.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		startDrag(input)
	end
end)

dot.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		startDrag(input)
	end
end)

UIS.InputChanged:Connect(function(input)
	if not dragging then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local d = input.Position - dragStart
		movedPx = movedPx + math.abs(d.X) + math.abs(d.Y)
		root.Position = UDim2.new(dragBase.X.Scale, dragBase.X.Offset + d.X, dragBase.Y.Scale, dragBase.Y.Offset + d.Y)
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if dragging then
			endDrag()
		end
	end
end)

--=====================================================================
-- 10. LOOP
--=====================================================================
local hb = RunService.Heartbeat:Connect(function(dt)
	protectionBeat()
	if Noclip.on then
		status.Text = "walls off  " .. tostring(Noclip.frame)
	elseif Noclip.err ~= "ok" then
		status.Text = "check"
	end
end)
table.insert(Noclip.conns, hb)

local stepped = RunService.Stepped:Connect(function()
	if Noclip.on then
		local _, _, hum = getChar()
		if hum and hum.MoveDirection.Magnitude > 0.1 then
			local _, hrp = getChar()
			if hrp and not hrp.Anchored then
				local c = LP.Character
				if c then
					for _, d in ipairs(c:GetChildren()) do
						if d:IsA("BasePart") and d.CanCollide then
							d.CanCollide = false
						end
					end
				end
			end
		end
	end
end)
table.insert(Noclip.conns, stepped)

print("bestnoclip loaded - 1517 guards armed")
--[[ protection1000.lua | owner supercaptain1233
     1000 guards, all protection, auto armed ]]

local P_GUARDS = 1000
local P_SLICE = 60
local P_KINDS = 12
local P_GHOST = 0.55

local P = {
	cursor = 0,
	frame = 0,
	armed = true,
	conns = {},
	err = "ok",
	gui = nil,
	btn = nil,
	hooked = false,
}

local function pSafe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		P.err = tostring(err)
	end
	return ok
end

local function pChar()
	local c = LP.Character
	if not c then
		return nil, nil, nil
	end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return nil, nil, nil
	end
	return c, hrp, hum
end

local function findGui()
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	return pg:FindFirstChild("bestnoclip")
end

local function getBtn()
	if P.btn and P.btn.Parent then
		return P.btn
	end
	local g = P.gui
	if not g then
		return nil
	end
	for _, d in ipairs(g:GetDescendants()) do
		if d:IsA("TextButton") and (d.Text == "NOCLIP" or d.Text == "GHOST ON") then
			P.btn = d
			return d
		end
	end
	return nil
end

local function ghostOn()
	local b = getBtn()
	return b ~= nil and b.Text == "GHOST ON"
end

local function pWatch(d)
	if not d or not d:IsA("BasePart") then
		return
	end
	d.CanCollide = false
	pSafe(function()
		d.Transparency = P_GHOST
	end)
end

local function hookChar(c)
	if P.hooked then
		return
	end
	P.hooked = true
	c.DescendantAdded:Connect(function(d)
		if ghostOn() then
			pSafe(pWatch, d)
		end
	end)
end

local function pKill(i)
	local c = LP.Character
	if not c then
		return
	end
	local parts = c:GetDescendants()
	local n = #parts
	if n == 0 then
		return
	end
	local p = parts[((i * 13) % n) + 1]
	if p and p:IsA("BasePart") then
		if p.CanCollide then
			p.CanCollide = false
		end
	end
end

local function pGhost(i)
	local c = LP.Character
	if not c then
		return
	end
	local parts = c:GetDescendants()
	local n = #parts
	if n == 0 then
		return
	end
	local p = parts[((i * 17) % n) + 1]
	if p and p:IsA("BasePart") and p.Transparency < 0.4 then
		p.Transparency = P_GHOST
	end
end

local function runP(i)
	local kind = (i % P_KINDS) + 1
	if kind == 1 then
		if ghostOn() then
			pKill(i)
		end
	elseif kind == 2 then
		if ghostOn() then
			pGhost(i)
		end
	elseif kind == 3 then
		local pg = LP:FindFirstChildOfClass("PlayerGui")
		local g = P.gui
		if not g or not g.Parent then
			P.gui = findGui()
			P.btn = nil
		elseif pg and g.Parent ~= pg then
			pSafe(function()
				g.Parent = pg
			end)
		end
	elseif kind == 4 then
		if P.gui and not P.gui.Enabled then
			P.gui.Enabled = true
		end
	elseif kind == 5 then
		local _, hrp = pChar()
		if hrp and hrp.Anchored and ghostOn() then
			hrp.Anchored = false
		end
	elseif kind == 6 then
		if Workspace.CurrentCamera and Workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable then
			Workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
		end
	elseif kind == 7 then
		if ghostOn() then
			local _, _, hum = pChar()
			if hum and hum.WalkSpeed <= 0 then
				hum.WalkSpeed = 16
			end
		end
	elseif kind == 8 then
		if ghostOn() then
			local _, _, hum = pChar()
			if hum then
				if hum.PlatformStand then
					hum.PlatformStand = false
				end
				if hum:GetState() == Enum.HumanoidStateType.Physics then
					hum:ChangeState(Enum.HumanoidStateType.Running)
				end
			end
		end
	elseif kind == 9 then
		if #P.conns > 600 then
			local old = table.remove(P.conns, 1)
			if old then
				pSafe(function()
					old:Disconnect()
				end)
			end
		end
	elseif kind == 10 then
		if ghostOn() then
			local c = LP.Character
			if c then
				hookChar(c)
				for _, d in ipairs(c:GetChildren()) do
					if d:IsA("BasePart") then
						pWatch(d)
					end
				end
			end
		end
	elseif kind == 11 then
		if ghostOn() then
			local _, hrp = pChar()
			if hrp then
				for _, d in ipairs(hrp:GetChildren()) do
					if d:IsA("BasePart") and d.CanCollide then
						d.CanCollide = false
					end
				end
			end
		end
	else
		P.frame = P.frame + 1
	end
end

P.gui = findGui()
if LP.Character then
	hookChar(LP.Character)
end
LP.CharacterAdded:Connect(function(c)
	P.hooked = false
	task.wait(0.15)
	hookChar(c)
end)

table.insert(P.conns, RunService.Heartbeat:Connect(function()
	if not P.armed then
		return
	end
	for _ = 1, P_SLICE do
		P.cursor = (P.cursor % P_GUARDS) + 1
		pSafe(runP, P.cursor)
	end
end))

table.insert(P.conns, RunService.Stepped:Connect(function()
	if not ghostOn() then
		return
	end
	local c = LP.Character
	if c then
		for _, d in ipairs(c:GetChildren()) do
			if d:IsA("BasePart") and d.CanCollide then
				d.CanCollide = false
			end
		end
	end
end))
--[[ protection1000b.lua | owner supercaptain1233
     second layer, 1000 guards, different jobs than the first ]]

local Q_GUARDS = 1000
local Q_SLICE = 60
local Q_KINDS = 14
local Q_SNAP = 10

local Q = {
	cursor = 0,
	frame = 0,
	armed = true,
	conns = {},
	err = "ok",
	gui = nil,
	btn = nil,
	good = nil,
	solids = 0,
	rebuilds = 0,
	hooked = false,
}

local function qSafe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		Q.err = tostring(err)
	end
	return ok
end

local function qChar()
	local c = LP.Character
	if not c then
		return nil, nil, nil
	end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return nil, nil, nil
	end
	return c, hrp, hum
end

local function qGui()
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	return pg:FindFirstChild("bestnoclip")
end

local function qBtn()
	if Q.btn and Q.btn.Parent then
		return Q.btn
	end
	local g = Q.gui
	if not g then
		return nil
	end
	for _, d in ipairs(g:GetDescendants()) do
		if d:IsA("TextButton") and (d.Text == "NOCLIP" or d.Text == "GHOST ON") then
			Q.btn = d
			return d
		end
	end
	return nil
end

local function qGhost()
	local b = qBtn()
	return b ~= nil and b.Text == "GHOST ON"
end

-- wipe every solid part in one go, and count how many there were
local function solidWipe()
	local c = LP.Character
	if not c then
		return
	end
	local n = 0
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide then
			d.CanCollide = false
			n = n + 1
		end
	end
	Q.solids = n
end

-- if the game drags you backwards, put you back where you were
local function posKeep()
	local _, hrp, hum = qChar()
	if not hrp or not hum then
		Q.good = nil
		return
	end
	if hrp.Anchored or hum.MoveDirection.Magnitude < 0.1 then
		Q.good = hrp.Position
		return
	end
	if not Q.good then
		Q.good = hrp.Position
		return
	end
	local move = hrp.Position - Q.good
	if move.Magnitude > Q_SNAP and move:Dot(hum.MoveDirection) < 0 then
		local rot = hrp.CFrame - hrp.CFrame.Position
		pSafe = qSafe
		qSafe(function()
			hrp.CFrame = CFrame.new(Q.good) * rot
		end)
		Q.rebuilds = Q.rebuilds + 1
	else
		Q.good = hrp.Position
	end
end

local function qHook(c)
	if Q.hooked then
		return
	end
	Q.hooked = true
	c.DescendantAdded:Connect(function(d)
		if qGhost() and d:IsA("BasePart") then
			d.CanCollide = false
			qSafe(function()
				d.Transparency = 0.55
			end)
		end
	end)
end

local function qKill(i)
	local c = LP.Character
	if not c then
		return
	end
	local parts = c:GetDescendants()
	local n = #parts
	if n == 0 then
		return
	end
	local p = parts[((i * 19) % n) + 1]
	if p and p:IsA("BasePart") and p.CanCollide then
		p.CanCollide = false
	end
end

local function qTools()
	local c = LP.Character
	if not c then
		return
	end
	for _, d in ipairs(c:GetChildren()) do
		if d:IsA("Tool") then
			for _, p in ipairs(d:GetDescendants()) do
				if p:IsA("BasePart") and p.CanCollide then
					p.CanCollide = false
				end
			end
		end
	end
end

local function runQ(i)
	local kind = (i % Q_KINDS) + 1
	if kind == 1 then
		if qGhost() then
			qKill(i)
		end
	elseif kind == 2 then
		if qGhost() and Q.solids > 0 then
			solidWipe()
		end
	elseif kind == 3 then
		if qGhost() then
			posKeep()
		end
	elseif kind == 4 then
		if qGhost() then
			local _, _, hum = qChar()
			if hum then
				if hum.PlatformStand then
					hum.PlatformStand = false
				end
				if hum:GetState() == Enum.HumanoidStateType.Physics then
					hum:ChangeState(Enum.HumanoidStateType.Running)
				end
				if hum:GetState() == Enum.HumanoidStateType.Landed then
					hum:ChangeState(Enum.HumanoidStateType.Running)
				end
			end
		end
	elseif kind == 5 then
		if qGhost() then
			local _, _, hum = qChar()
			if hum and hum.WalkSpeed < 16 then
				hum.WalkSpeed = 16
			end
		end
	elseif kind == 6 then
		if qGhost() then
			local _, _, hum = qChar()
			if hum and hum.JumpPower and hum.JumpPower < 50 then
				hum.JumpPower = 50
			end
		end
	elseif kind == 7 then
		local _, hrp = qChar()
		if hrp and hrp.Anchored and qGhost() then
			hrp.Anchored = false
		end
	elseif kind == 8 then
		local cam = Workspace.CurrentCamera
		if cam and cam.CameraType == Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
	elseif kind == 9 then
		local pg = LP:FindFirstChildOfClass("PlayerGui")
		local g = Q.gui
		if not g or not g.Parent then
			Q.gui = qGui()
			Q.btn = nil
		elseif pg and g.Parent ~= pg then
			qSafe(function()
				g.Parent = pg
			end)
		end
		if Q.gui and not Q.gui.Enabled then
			Q.gui.Enabled = true
		end
	elseif kind == 10 then
		if qGhost() then
			qTools()
		end
	elseif kind == 11 then
		if #Q.conns > 600 then
			local old = table.remove(Q.conns, 1)
			if old then
				qSafe(function()
					old:Disconnect()
				end)
			end
		end
	elseif kind == 12 then
		if qGhost() then
			local c = LP.Character
			if c then
				qHook(c)
				for _, d in ipairs(c:GetChildren()) do
					if d:IsA("BasePart") then
						d.CanCollide = false
					end
				end
			end
		end
	elseif kind == 13 then
		if qGhost() then
			local _, hrp = qChar()
			if hrp then
				for _, d in ipairs(hrp:GetChildren()) do
					if d:IsA("BasePart") and d.CanCollide then
						d.CanCollide = false
					end
				end
			end
		end
	else
		Q.frame = Q.frame + 1
	end
end

Q.gui = qGui()
if LP.Character then
	qHook(LP.Character)
end
LP.CharacterAdded:Connect(function(c)
	Q.hooked = false
	Q.good = nil
	task.wait(0.15)
	qHook(c)
end)

table.insert(Q.conns, RunService.Heartbeat:Connect(function()
	if not Q.armed then
		return
	end
	for _ = 1, Q_SLICE do
		Q.cursor = (Q.cursor % Q_GUARDS) + 1
		qSafe(runQ, Q.cursor)
	end
end))

table.insert(Q.conns, RunService.RenderStepped:Connect(function()
	if not qGhost() then
		return
	end
	local c = LP.Character
	if not c then
		return
	end
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide then
			d.CanCollide = false
		end
	end
end))
--[[ noclip1000.lua | owner supercaptain1233
     third layer, 1000 guards, all wall passing ]]

local R_GUARDS = 1000
local R_SLICE = 60
local R_KINDS = 14
local R_PROBE = 3.5
local R_PUSH = 0.75
local R_LIFT = 2.2

local R = {
	cursor = 0,
	frame = 0,
	armed = true,
	conns = {},
	err = "ok",
	gui = nil,
	btn = nil,
	pushes = 0,
	lifts = 0,
	hooked = false,
	parts = {},
}

local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Exclude
rp.FilterDescendantsInstances = {}

local function rSafe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		R.err = tostring(err)
	end
	return ok
end

local function rChar()
	local c = LP.Character
	if not c then
		return nil, nil, nil
	end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return nil, nil, nil
	end
	return c, hrp, hum
end

local function rGui()
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	return pg:FindFirstChild("bestnoclip")
end

local function rBtn()
	if R.btn and R.btn.Parent then
		return R.btn
	end
	local g = R.gui
	if not g then
		return nil
	end
	for _, d in ipairs(g:GetDescendants()) do
		if d:IsA("TextButton") and (d.Text == "NOCLIP" or d.Text == "GHOST ON") then
			R.btn = d
			return d
		end
	end
	return nil
end

local function rGhost()
	local b = rBtn()
	return b ~= nil and b.Text == "GHOST ON"
end

-- take collision off everything you are touching, including handles
local function rDeep(c)
	if not c then
		return
	end
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.CanCollide then
				d.CanCollide = false
			end
			if d.Transparency < 0.4 then
				d.Transparency = 0.55
			end
		end
	end
end

-- look at what is in front of you and shove through it
local function rPush()
	local c, hrp, hum = rChar()
	if not hrp or not hum then
		return
	end
	local md = hum.MoveDirection
	if md.Magnitude < 0.1 then
		return
	end
	rp.FilterDescendantsInstances = { c }
	local hit = Workspace:Raycast(hrp.Position, md.Unit * R_PROBE, rp)
	if hit then
		rSafe(function()
			hrp.CFrame = hrp.CFrame + md.Unit * R_PUSH
		end)
		R.pushes = R.pushes + 1
	end
end

-- if you are jammed into the floor, lift out
local function rLift()
	local _, hrp, hum = rChar()
	if not hrp or not hum then
		return
	end
	if hum.MoveDirection.Magnitude < 0.1 then
		return
	end
	local down = Workspace:Raycast(hrp.Position, Vector3.new(0, -2.6, 0), rp)
	if down and down.Distance < 1.4 then
		rSafe(function()
			hrp.CFrame = hrp.CFrame + Vector3.new(0, R_LIFT, 0)
		end)
		R.lifts = R.lifts + 1
	end
end

local function rHook(c)
	if R.hooked then
		return
	end
	R.hooked = true
	c.DescendantAdded:Connect(function(d)
		if rGhost() and d:IsA("BasePart") then
			d.CanCollide = false
			rSafe(function()
				d.Transparency = 0.55
			end)
		end
	end)
end

local function rKill(i)
	local c = LP.Character
	if not c then
		return
	end
	local parts = c:GetDescendants()
	local n = #parts
	if n == 0 then
		return
	end
	local p = parts[((i * 23) % n) + 1]
	if p and p:IsA("BasePart") and p.CanCollide then
		p.CanCollide = false
	end
end

local function rState()
	local _, _, hum = rChar()
	if not hum then
		return
	end
	if hum.PlatformStand then
		hum.PlatformStand = false
	end
	if hum.Sit then
		hum.Sit = false
	end
	local st = hum:GetState()
	if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Landed or st == Enum.HumanoidStateType.FallingDown then
		hum:ChangeState(Enum.HumanoidStateType.Running)
	end
end

local function runR(i)
	local kind = (i % R_KINDS) + 1
	if kind == 1 then
		if rGhost() then
			rKill(i)
		end
	elseif kind == 2 then
		if rGhost() and R.frame % 6 == 0 then
			rPush()
		end
	elseif kind == 3 then
		if rGhost() and R.frame % 9 == 0 then
			rLift()
		end
	elseif kind == 4 then
		if rGhost() then
			rState()
		end
	elseif kind == 5 then
		if rGhost() then
			local _, hrp = rChar()
			if hrp and hrp.CanCollide then
				hrp.CanCollide = false
			end
		end
	elseif kind == 6 then
		if rGhost() then
			local _, _, hum = rChar()
			if hum and hum.WalkSpeed < 16 then
				hum.WalkSpeed = 16
			end
		end
	elseif kind == 7 then
		if rGhost() then
			local _, hrp = rChar()
			if hrp and hrp.Anchored then
				hrp.Anchored = false
			end
		end
	elseif kind == 8 then
		if rGhost() then
			local c = LP.Character
			if c then
				rHook(c)
				rDeep(c)
			end
		end
	elseif kind == 9 then
		if rGhost() then
			local c = LP.Character
			if c then
				for _, d in ipairs(c:GetChildren()) do
					if d:IsA("Tool") or d:IsA("Accessory") then
						rDeep(d)
					end
				end
			end
		end
	elseif kind == 10 then
		if rGhost() then
			local _, hrp = rChar()
			if hrp then
				for _, d in ipairs(hrp:GetChildren()) do
					if d:IsA("BasePart") and d.CanCollide then
						d.CanCollide = false
					end
				end
			end
		end
	elseif kind == 11 then
		local pg = LP:FindFirstChildOfClass("PlayerGui")
		local g = R.gui
		if not g or not g.Parent then
			R.gui = rGui()
			R.btn = nil
		elseif pg and g.Parent ~= pg then
			rSafe(function()
				g.Parent = pg
			end)
		end
	elseif kind == 12 then
		if #R.conns > 600 then
			local old = table.remove(R.conns, 1)
			if old then
				rSafe(function()
					old:Disconnect()
				end)
			end
		end
	elseif kind == 13 then
		local cam = Workspace.CurrentCamera
		if cam and cam.CameraType == Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
	else
		R.frame = R.frame + 1
	end
end

R.gui = rGui()
if LP.Character then
	rHook(LP.Character)
end
LP.CharacterAdded:Connect(function(c)
	R.hooked = false
	task.wait(0.15)
	rHook(c)
end)

table.insert(R.conns, RunService.Heartbeat:Connect(function()
	if not R.armed then
		return
	end
	for _ = 1, R_SLICE do
		R.cursor = (R.cursor % R_GUARDS) + 1
		rSafe(runR, R.cursor)
	end
end))

table.insert(R.conns, RunService.Stepped:Connect(function()
	if not rGhost() then
		return
	end
	local c = LP.Character
	if not c then
		return
	end
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide then
			d.CanCollide = false
		end
	end
end))
