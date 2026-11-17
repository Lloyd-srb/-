--!strict
--[[
	EffectController — small client-side visuals for abilities:
	  - stun-gun tracers (the server sends the start and end points);
	  - stars over anyone who is stunned (the server sets the body's
	    "Stunned" attribute);
	  - private toasts: "You blessed ...", "The attack was blocked!", "Stunned!".
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local TRACER_SECONDS = 0.15
local TRACER_COLOR = Color3.fromRGB(120, 210, 255)
local TOAST_SECONDS = 2.5
local STUN_TAG = "StunStars"

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

local function tracer(from: Vector3, to: Vector3)
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
	beam.Color = TRACER_COLOR
	beam.Size = Vector3.new(0.15, 0.15, length)
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	beam.Parent = workspace
	task.delay(TRACER_SECONDS, function()
		beam:Destroy()
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

local function watch(body: Instance)
	if watched[body] then
		return
	end
	watched[body] = true
	local function update()
		local stunned = body:GetAttribute("Stunned") == true
		setStars(body, stunned)
		if stunned and body == Players.LocalPlayer.Character then
			showToast(Loc.format("Effect.Stunned"))
		end
	end
	body:GetAttributeChangedSignal("Stunned"):Connect(update)
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
		tracer(data.From, data.To)
	elseif data.Kind == "Blocked" then
		showToast(Loc.format("Effect.Blocked"))
	elseif data.Kind == "Blessed" and type(data.Name) == "string" then
		showToast(Loc.format("Effect.Blessed", { name = data.Name }))
	elseif data.Kind == "Throw" and typeof(data.From) == "Vector3" and typeof(data.To) == "Vector3" then
		flyingAxe(data.From, data.To, if type(data.Speed) == "number" then data.Speed else 90)
	elseif data.Kind == "Gained" and type(data.Item) == "string" and Loc.has("Item." .. data.Item .. ".Name") then
		showToast(Loc.format("Effect.Gained", { item = Loc.format("Item." .. data.Item .. ".Name") }))
	elseif data.Kind == "TaskComplete" then
		showToast(Loc.format("Task.Complete", { coins = data.Coins }))
	elseif data.Kind == "CrossInfo" then
		showToast(Loc.format("Effect.CrossInfo"))
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
