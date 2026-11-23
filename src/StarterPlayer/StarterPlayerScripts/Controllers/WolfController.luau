--!strict
--[[
	WolfController — the wolf side's controls (GDD §8).
	Buttons exist on every platform through ContextActionService: keyboard /
	mouse, gamepad, and on-screen touch buttons. The client only sends "I
	pressed this"; the server decides what, if anything, happens.

	  Attack  left mouse / R2 / touch      (every monster form)
	  Skills  the Roblox hotbar (owner, 23 Nov 2026): the server puts each
	          skill in the backpack as a Tool; pressing its number uses it at
	          once. Cooldowns show on the hotbar (the tool's name, locally).
	Camera: always shift lock while a monster (owner, 23 Nov 2026): the mouse
	is locked to the centre and the body turns with the camera.
	Gamepad X is left to the "hold" prompts (searching hiding spots).
	Touch buttons use Roblox's own layout around the jump button.
	Vision (owner, 18 Nov 2026): in werewolf form the night fog on this
	screen follows the monster's Vision stat (Config.Wolf.NightVision).
]]

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Loc = require(ReplicatedStorage.Shared.Loc)

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ClientState = require(script.Parent.ClientState)

type Action = {
	Id: string,
	Forms: { string },
	Ability: string?, -- nil = the attack
	TitleKey: string,
	Sink: boolean?, -- keep the key from Roblox's own uses (shift lock)
	Inputs: { Enum.KeyCode | Enum.UserInputType },
}

local ACTIONS: { Action } = {
	{
		Id = "WolfAttack",
		Forms = { "Wolf", "Pup", "Lurker" },
		Ability = nil,
		TitleKey = "Ability.Attack",
		Inputs = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
	},
}

local WolfController = {}

local bound: { [string]: boolean } = {}
local readyAt: { [string]: number } = {} -- ability -> server time

local function title(action: Action): string
	local text = Loc.format(action.TitleKey)
	local ability = action.Ability
	if ability then
		local left = (readyAt[ability] or 0) - workspace:GetServerTimeNow()
		if left > 0 then
			return string.format("%s %d", text, math.ceil(left))
		end
	end
	return text
end

local function bind(action: Action)
	if bound[action.Id] then
		return
	end
	bound[action.Id] = true
	ContextActionService:BindActionAtPriority(action.Id, function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			if action.Ability then
				Remotes.get("WolfAbility"):FireServer(action.Ability)
			else
				Remotes.get("WolfAttack"):FireServer()
			end
		end
		return if action.Sink then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
	end, true, Enum.ContextActionPriority.High.Value, table.unpack(action.Inputs))
	ContextActionService:SetTitle(action.Id, title(action))
end

local function unbind(action: Action)
	if bound[action.Id] then
		bound[action.Id] = nil
		ContextActionService:UnbindAction(action.Id)
	end
end

local VISION_BIND = "WolfVision"
local visionBound = false
local visionForm = ""

-- How far each monster sees at night (its Vision bar).
local function visionFor(form: string): number
	if form == "Lurker" then
		return Config.monsterStat("Lurker", "Vision")
	end
	return Config.Wolf.NightVision
end

-- How far the werewolf sees at night: the fog on this screen only.
local function setVision(on: boolean)
	if on == visionBound then
		return
	end
	visionBound = on
	if not on then
		RunService:UnbindFromRenderStep(VISION_BIND)
		return
	end
	local night = Config.Lighting.Night
	local fogEnd = visionFor(ClientState.Form)
	local fogStart = fogEnd * night.FogStart / night.FogEnd
	RunService:BindToRenderStep(VISION_BIND, Enum.RenderPriority.Last.Value, function()
		-- The server's night preset replicates over this; set it back each frame.
		if Lighting.FogEnd ~= fogEnd then
			Lighting.FogEnd = fogEnd
			Lighting.FogStart = fogStart
		end
	end)
end

-- Shift lock, always on for a monster (owner, 23 Nov 2026): the mouse stays in
-- the centre, the camera sits over the shoulder and the body faces where the
-- camera looks (so a water bolt goes where you look).
local SHIFT_LOCK_BIND = "MonsterShiftLock"
local SHIFT_LOCK_OFFSET = Vector3.new(1.75, 0, 0) -- like Roblox's own shift lock
local shiftLocked = false
local gameOver = false

local function setShiftLock(on: boolean)
	if on == shiftLocked then
		return
	end
	shiftLocked = on
	if not on then
		RunService:UnbindFromRenderStep(SHIFT_LOCK_BIND)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.AutoRotate = true
			humanoid.CameraOffset = Vector3.zero
		end
		return
	end
	RunService:BindToRenderStep(SHIFT_LOCK_BIND, Enum.RenderPriority.Camera.Value + 1, function()
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = workspace.CurrentCamera
		if not humanoid or not (root and root:IsA("BasePart")) or not camera then
			return
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		humanoid.AutoRotate = false
		humanoid.CameraOffset = SHIFT_LOCK_OFFSET
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 1e-3 then
			local position = root.CFrame.Position
			root.CFrame = CFrame.lookAt(position, position + flat.Unit)
		end
	end)
end

local function refresh()
	local monster = ClientState.Form == "Wolf" or ClientState.Form == "Pup" or ClientState.Form == "Lurker"
	setShiftLock(ClientState.Alive and monster and not gameOver)
	local beast = ClientState.Form == "Wolf" or ClientState.Form == "Lurker"
	if visionBound and visionForm ~= ClientState.Form then
		setVision(false) -- another monster: start again with its own distance
	end
	visionForm = ClientState.Form
	setVision(ClientState.Alive and beast and visionFor(ClientState.Form) ~= Config.Lighting.Night.FogEnd)
	for _, action in ACTIONS do
		if ClientState.Alive and table.find(action.Forms, ClientState.Form) then
			bind(action)
		else
			unbind(action)
		end
	end
end

-- Names of the pack for the HUD (wolf side only ever receives this).
local function showPack(ids: any, names: { [number]: string })
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("Hud")
	local label = hud and hud:FindFirstChild("PackLabel")
	if not (label and label:IsA("TextLabel")) or type(ids) ~= "table" then
		return
	end
	local list = {}
	for _, id in ids do
		table.insert(list, names[id] or tostring(id))
	end
	label.Text = Loc.format("Hud.Pack", { names = table.concat(list, ", ") })
	label.Visible = #list > 1
end

function WolfController.Start()
	local names: { [number]: string } = {}
	local packIds: any = {}

	Remotes.get("RosterChanged").OnClientEvent:Connect(function(roster: any)
		if type(roster) == "table" then
			for _, entry in roster do
				names[entry.Id] = entry.Name
			end
			showPack(packIds, names)
		end
	end)
	Remotes.get("PackChanged").OnClientEvent:Connect(function(ids: any)
		packIds = ids
		showPack(packIds, names)
	end)

	Remotes.get("FormChanged").OnClientEvent:Connect(function(form: any)
		if type(form) == "string" then
			ClientState.set("Form", form)
			refresh()
		end
	end)
	ClientState.Changed:Connect(function(key: string)
		if key == "Alive" then
			refresh()
		end
	end)
	-- The scoreboard needs the mouse.
	Remotes.get("GameOver").OnClientEvent:Connect(function()
		gameOver = true
		refresh()
	end)
	Remotes.get("AbilityState").OnClientEvent:Connect(function(data: any)
		if type(data) == "table" and type(data.Name) == "string" and type(data.ReadyAt) == "number" then
			readyAt[data.Name] = data.ReadyAt
		end
	end)

	-- Cooldown numbers: on the attack button and on the hotbar skills.
	task.spawn(function()
		while true do
			for _, action in ACTIONS do
				if bound[action.Id] then
					ContextActionService:SetTitle(action.Id, title(action))
				end
			end
			local backpack = Players.LocalPlayer:FindFirstChildOfClass("Backpack")
			if backpack then
				for _, tool in backpack:GetChildren() do
					local skill = tool:GetAttribute("MonsterSkill")
					if tool:IsA("Tool") and type(skill) == "string" then
						local text = Loc.format("Ability." .. skill)
						local left = (readyAt[skill] or 0) - workspace:GetServerTimeNow()
						local wanted = if left > 0 then string.format("%s %d", text, math.ceil(left)) else text
						if tool.Name ~= wanted then
							tool.Name = wanted -- only on this screen
						end
					end
				end
			end
			task.wait(0.25)
		end
	end)
end

return WolfController
