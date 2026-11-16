--!strict
--[[
	WolfController — the wolf side's controls (GDD §8).
	Buttons exist on every platform through ContextActionService: keyboard /
	mouse, gamepad, and on-screen touch buttons. The client only sends "I
	pressed this"; the server decides what, if anything, happens.

	  Attack  left mouse / R2 / touch      (wolf and pup)
	  Sniff   Q / X                        (wolf)
	  Sprint  Left Shift / Y               (wolf)
	  Howl    Q / X                        (pup)
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ClientState = require(script.Parent.ClientState)

type Action = {
	Id: string,
	Forms: { string },
	Ability: string?, -- nil = the attack
	TitleKey: string,
	Position: UDim2,
	Inputs: { Enum.KeyCode | Enum.UserInputType },
}

local ACTIONS: { Action } = {
	{
		Id = "WolfAttack",
		Forms = { "Wolf", "Pup" },
		Ability = nil,
		TitleKey = "Ability.Attack",
		Position = UDim2.new(1, -150, 1, -150),
		Inputs = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
	},
	{
		Id = "WolfSniff",
		Forms = { "Wolf" },
		Ability = "Sniff",
		TitleKey = "Ability.Sniff",
		Position = UDim2.new(1, -230, 1, -110),
		Inputs = { Enum.KeyCode.Q, Enum.KeyCode.ButtonX },
	},
	{
		Id = "WolfSprint",
		Forms = { "Wolf" },
		Ability = "Sprint",
		TitleKey = "Ability.Sprint",
		Position = UDim2.new(1, -210, 1, -200),
		Inputs = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonY },
	},
	{
		Id = "PupHowl",
		Forms = { "Pup" },
		Ability = "Howl",
		TitleKey = "Ability.Howl",
		Position = UDim2.new(1, -230, 1, -110),
		Inputs = { Enum.KeyCode.Q, Enum.KeyCode.ButtonX },
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
	ContextActionService:BindAction(action.Id, function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			if action.Ability then
				Remotes.get("WolfAbility"):FireServer(action.Ability)
			else
				Remotes.get("WolfAttack"):FireServer()
			end
		end
		return Enum.ContextActionResult.Pass
	end, true, table.unpack(action.Inputs))
	ContextActionService:SetPosition(action.Id, action.Position)
	ContextActionService:SetTitle(action.Id, title(action))
end

local function unbind(action: Action)
	if bound[action.Id] then
		bound[action.Id] = nil
		ContextActionService:UnbindAction(action.Id)
	end
end

local function refresh()
	for _, action in ACTIONS do
		if table.find(action.Forms, ClientState.Form) then
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
