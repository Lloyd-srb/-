--!strict
--[[
	WolfController — the wolf side's controls (GDD §8).
	Buttons exist on every platform through ContextActionService: keyboard /
	mouse, gamepad, and on-screen touch buttons. The client only sends "I
	pressed this"; the server decides what, if anything, happens.

	  Attack  left mouse / R2 / touch      (wolf and pup)
	  Sniff   Q / L2                       (wolf)
	  Sprint  Left Shift / Y               (wolf; taken before Roblox's shift lock)
	  Howl    Q / L2                       (pup)
	Gamepad X is left to the "hold" prompts (searching hiding spots).
	Touch buttons use Roblox's own layout around the jump button.
	Vision (owner, 18 Nov 2026): in werewolf form the night fog on this
	screen follows the monster's Vision stat (Config.Wolf.NightVision).
]]

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Loc = require(ReplicatedStorage.Shared.Loc)

local Aim = require(script.Parent.Aim)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ClientState = require(script.Parent.ClientState)

type Action = {
	Id: string,
	Forms: { string },
	Ability: string?, -- nil = the attack
	TitleKey: string,
	Sink: boolean?, -- keep the key from Roblox's own uses (shift lock)
	Aimed: boolean?, -- sends the aim direction (mouse / camera) with the press
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
	{
		Id = "WolfSniff",
		Forms = { "Wolf" },
		Ability = "Sniff",
		TitleKey = "Ability.Sniff",
		Inputs = { Enum.KeyCode.Q, Enum.KeyCode.ButtonL2 },
	},
	{
		Id = "WolfSprint",
		Forms = { "Wolf" },
		Ability = "Sprint",
		TitleKey = "Ability.Sprint",
		Sink = true,
		Inputs = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonY },
	},
	{
		Id = "PupHowl",
		Forms = { "Pup" },
		Ability = "Howl",
		TitleKey = "Ability.Howl",
		Inputs = { Enum.KeyCode.Q, Enum.KeyCode.ButtonL2 },
	},
	-- The Lurker (owner, 19 / 23 Nov 2026).
	{
		Id = "LurkerWaterBolt",
		Forms = { "Lurker" },
		Ability = "WaterBolt",
		TitleKey = "Ability.WaterBolt",
		Aimed = true,
		Inputs = { Enum.KeyCode.Q, Enum.KeyCode.ButtonL2 },
	},
	{
		Id = "LurkerVanish",
		Forms = { "Lurker" },
		Ability = "Vanish",
		TitleKey = "Ability.Vanish",
		Sink = true,
		Inputs = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonY },
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
	ContextActionService:BindActionAtPriority(action.Id, function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			if action.Ability and action.Aimed then
				local fromTouch = input.UserInputType == Enum.UserInputType.Touch
				local direction = Aim.direction(Config.Lurker.Bullet.Range, fromTouch)
				if direction then
					Remotes.get("WolfAbility"):FireServer(action.Ability, direction)
				end
			elseif action.Ability then
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

local function refresh()
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
	Remotes.get("AbilityState").OnClientEvent:Connect(function(data: any)
		if type(data) == "table" and type(data.Name) == "string" and type(data.ReadyAt) == "number" then
			readyAt[data.Name] = data.ReadyAt
		end
	end)

	-- Cooldown numbers on the buttons.
	task.spawn(function()
		while true do
			for _, action in ACTIONS do
				if bound[action.Id] then
					ContextActionService:SetTitle(action.Id, title(action))
				end
			end
			task.wait(0.25)
		end
	end)
end

return WolfController
