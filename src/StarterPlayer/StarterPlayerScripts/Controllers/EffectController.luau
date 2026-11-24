--!strict
--[[
	EffectController — small client-side visuals for abilities:
	  - stun-gun tracers (the server sends the start and end points, and the
	    shooter's gun skin colour) and the Killer's slash (knife skin colour);
	  - stars over anyone who is stunned (the server sets the body's
	    "Stunned" attribute);
	  - private toasts: "You blessed ...", "The attack was blocked!", "Stunned!";
	  - the Ninja's smoke puff, and the Ninja seeing their own invisible body
	    faintly (owner, 24 Nov 2026).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local TRACER_SECONDS = 0.15
local TRACER_COLOR = Color3.fromRGB(120, 210, 255)
local TOAST_SECONDS = 2.5
local SLASH_SECONDS = 0.35
local STUN_TAG = "StunStars"
local SMOKE_SECONDS = 0.8
local OWN_SMOKE_TRANSPARENCY = 0.75 -- how the Ninja sees their own invisible body

local EffectController = {}

local toast: TextLabel? = nil
local toastToken = 0
local watched: { [Instance]: boolean } = {}

local function showToast(text: string)
	local label = toast
	if not label then
		return
	end
	toastToken += 1
	local token = toastToken
	label.Text = text
	label.Visible = true
	task.delay(TOAST_SECONDS, function()
		if toastToken == token then
			label.Visible = false
		end
	end)
end

local function tracer(from: Vector3, to: Vector3, color: Color3?)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "ShotTracer"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color or TRACER_COLOR
	beam.Size = Vector3.new(0.15, 0.15, length)
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	beam.Parent = workspace
	task.delay(TRACER_SECONDS, function()
		beam:Destroy()
	end)
end

-- A quick arc where the Killer's knife struck (knife skin colour).
local function slash(at: Vector3, color: Color3)
	local arc = Instance.new("Part")
	arc.Name = "Slash"
	arc.Anchored = true
	arc.CanCollide = false
	arc.CanQuery = false
	arc.CanTouch = false
	arc.CastShadow = false
	arc.Material = Enum.Material.Neon
	arc.Color = color
	arc.Transparency = 0.2
	arc.Size = Vector3.new(0.2, 0.2, 3.5)
	arc.CFrame = CFrame.new(at) * CFrame.Angles(0, math.rad(45), math.rad(35))
	arc.Parent = workspace
	TweenService:Create(arc, TweenInfo.new(SLASH_SECONDS), { Transparency = 1 }):Play()
	task.delay(SLASH_SECONDS, function()
		arc:Destroy()
	end)
end

-- A spinning axe flying from the thrower to where it landed.
local function flyingAxe(from: Vector3, to: Vector3, speed: number)
	local distance = (to - from).Magnitude
	if distance < 0.1 then
		return
	end
	local axe = Instance.new("Part")
	axe.Name = "ThrownAxe"
	axe.Anchored = true
	axe.CanCollide = false
	axe.CanQuery = false
	axe.CanTouch = false
	axe.Size = Vector3.new(0.4, 2.4, 0.4)
	axe.Color = Color3.fromRGB(150, 105, 60)
	axe.Parent = workspace
	local duration = distance / speed
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local alpha = math.min(1, (os.clock() - started) / duration)
		axe.CFrame = CFrame.new(from:Lerp(to, alpha)) * CFrame.Angles(alpha * 20, 0, 0)
		if alpha >= 1 then
			connection:Disconnect()
			axe:Destroy()
		end
	end)
end

-- The Lurker's water bolt: a blue ball flying from its mouth to where it hit.
local function waterBolt(from: Vector3, to: Vector3, speed: number)
	local distance = (to - from).Magnitude
	if distance < 0.1 then
		return
	end
	local ball = Instance.new("Part")
	ball.Name = "WaterBolt"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(1.2, 1.2, 1.2)
	ball.Color = Color3.fromRGB(90, 200, 255)
	ball.Material = Enum.Material.Neon
	ball.Transparency = 0.2
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Parent = workspace
	local duration = distance / speed
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local alpha = math.min(1, (os.clock() - started) / duration)
		ball.CFrame = CFrame.new(from:Lerp(to, alpha))
		if alpha >= 1 then
			connection:Disconnect()
			ball:Destroy()
		end
	end)
end

local function setStars(body: Instance, stunned: boolean)
	local existing = body:FindFirstChild(STUN_TAG)
	if not stunned then
		if existing then
			existing:Destroy()
		end
		return
	end
	local root = body:FindFirstChild("HumanoidRootPart")
	if existing or not root then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = STUN_TAG
	gui.Adornee = root :: BasePart
	gui.Size = UDim2.fromScale(3, 1)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = false
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "* * *"
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 230, 90)
	text.Parent = gui
	gui.Parent = body
end

-- A puff of grey smoke where the Ninja vanished.
local function smokePuff(at: Vector3)
	for index = 1, 5 do
		local puff = Instance.new("Part")
		puff.Name = "SmokePuff"
		puff.Shape = Enum.PartType.Ball
		puff.Size = Vector3.new(2, 2, 2)
		puff.Color = Color3.fromRGB(150, 150, 158)
		puff.Material = Enum.Material.SmoothPlastic
		puff.Transparency = 0.3
		puff.Anchored = true
		puff.CanCollide = false
		puff.CanQuery = false
		puff.CanTouch = false
		puff.CastShadow = false
		local angle = index * math.pi * 2 / 5
		puff.CFrame = CFrame.new(at + Vector3.new(math.cos(angle) * 1.2, (index % 2) * 1.5, math.sin(angle) * 1.2))
		puff.Parent = workspace
		TweenService:Create(puff, TweenInfo.new(SMOKE_SECONDS), { Size = Vector3.new(6, 6, 6), Transparency = 1 }):Play()
		task.delay(SMOKE_SECONDS, function()
			puff:Destroy()
		end)
	end
end

-- The Ninja sees their own invisible body faintly (only on this screen; the
-- server puts the real values back when the smoke ends).
local function showOwnSmoke(body: Instance)
	if body ~= Players.LocalPlayer.Character or body:GetAttribute("Vanished") ~= true then
		return
	end
	for _, part in body:GetDescendants() do
		local before = part:GetAttribute("SmokeTransparency")
		if type(before) == "number" and before < 1 then
			if part:IsA("BasePart") then
				part.Transparency = OWN_SMOKE_TRANSPARENCY
			elseif part:IsA("Decal") then
				part.Transparency = OWN_SMOKE_TRANSPARENCY
			end
		end
	end
end

local function watch(body: Instance)
	if watched[body] then
		return
	end
	watched[body] = true
	local function update()
		local stunned = body:GetAttribute("Stunned") == true
		-- No stars over someone nobody can see.
		setStars(body, stunned and body:GetAttribute("Vanished") ~= true)
		if stunned and body == Players.LocalPlayer.Character then
			showToast(Loc.format("Effect.Stunned"))
		end
	end
	body:GetAttributeChangedSignal("Stunned"):Connect(update)
	body:GetAttributeChangedSignal("Vanished"):Connect(function()
		update()
		task.defer(showOwnSmoke, body)
	end)
	body.Destroying:Connect(function()
		watched[body] = nil
	end)
	update()
end

local function onEffect(data: any)
	if type(data) ~= "table" then
		return
	end
	if data.Kind == "Shot" and typeof(data.From) == "Vector3" and typeof(data.To) == "Vector3" then
		tracer(data.From, data.To, if typeof(data.Color) == "Color3" then data.Color else nil)
	elseif data.Kind == "Slash" and typeof(data.At) == "Vector3" and typeof(data.Color) == "Color3" then
		slash(data.At, data.Color)
	elseif data.Kind == "Smoke" and typeof(data.At) == "Vector3" then
		smokePuff(data.At)
	elseif data.Kind == "Blocked" then
		showToast(Loc.format("Effect.Blocked"))
	elseif data.Kind == "Blessed" and type(data.Name) == "string" then
		showToast(Loc.format("Effect.Blessed", { name = data.Name }))
	elseif data.Kind == "WaterBolt" and typeof(data.From) == "Vector3" and typeof(data.To) == "Vector3" then
		waterBolt(data.From, data.To, if type(data.Speed) == "number" then data.Speed else 110)
	elseif data.Kind == "Throw" and typeof(data.From) == "Vector3" and typeof(data.To) == "Vector3" then
		flyingAxe(data.From, data.To, if type(data.Speed) == "number" then data.Speed else 90)
	elseif data.Kind == "Gained" and type(data.Item) == "string" and Loc.has("Item." .. data.Item .. ".Name") then
		showToast(Loc.format("Effect.Gained", { item = Loc.format("Item." .. data.Item .. ".Name") }))
	elseif data.Kind == "TaskComplete" then
		showToast(Loc.format("Task.Complete", { coins = data.Coins }))
	elseif data.Kind == "CrossInfo" then
		showToast(Loc.format("Effect.CrossInfo"))
	elseif data.Kind == "Stolen" and type(data.Item) == "string" and Loc.has("Item." .. data.Item .. ".Name") then
		showToast(Loc.format("Effect.Stolen", { item = Loc.format("Item." .. data.Item .. ".Name") }))
	elseif type(data.Kind) == "string" and Loc.has("Effect." .. data.Kind) then
		-- Boots, Poisoned, PotionRevived, PotionUsed, PotionNoTarget, StealNothing,
		-- Cuffed, LockedIn, StayedHome, WasOut, NoNightYet, Oil*, DayOnly, ...
		local name = if type(data.Name) == "string" then data.Name else ""
		showToast(Loc.format("Effect." .. data.Kind, { name = name }))
	end
end

function EffectController.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("Hud")
	toast = hud:WaitForChild("Toast") :: TextLabel

	Remotes.get("Effect").OnClientEvent:Connect(onEffect)
	CollectionService:GetInstanceAddedSignal("MemberBody"):Connect(watch)
	for _, body in CollectionService:GetTagged("MemberBody") do
		watch(body)
	end

end

return EffectController
