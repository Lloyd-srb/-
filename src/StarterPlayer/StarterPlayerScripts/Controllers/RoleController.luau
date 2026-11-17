--!strict
--[[
	RoleController — buttons for the special roles' abilities (GDD §9).
	Works on keyboard / mouse, gamepad and touch (ContextActionService). The
	client only sends "use ability X"; the server checks everything.

	  Sheriff    Shoot       R / R2      aims at the mouse (PC) or the screen centre
	  Killer     Stab        R / R2
	  Seer       See         Q / X
	  Bodyguard  Dash        Q / X
	  Monk       Bless       Q / X       opens a list of living players
	  Villager   Flashlight  F / Y
	Doctor and Engineer use "hold E" prompts on bodies / doors instead.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Aim = require(script.Parent.Aim)
local ClientState = require(script.Parent.ClientState)

type Action = {
	Id: string,
	Role: string,
	Ability: string,
	TitleKey: string,
	Position: UDim2,
	Inputs: { Enum.KeyCode | Enum.UserInputType },
}

local PRIMARY = UDim2.new(1, -150, 1, -150)
local SECONDARY = UDim2.new(1, -230, 1, -110)

local ACTIONS: { Action } = {
	{ Id = "RoleShoot", Role = "Sheriff", Ability = "Shoot", TitleKey = "Ability.Shoot", Position = PRIMARY, Inputs = { Enum.KeyCode.R, Enum.KeyCode.ButtonR2 } },
	{ Id = "RoleStab", Role = "Killer", Ability = "Stab", TitleKey = "Ability.Stab", Position = PRIMARY, Inputs = { Enum.KeyCode.R, Enum.KeyCode.ButtonR2 } },
	{ Id = "RoleSee", Role = "Seer", Ability = "See", TitleKey = "Ability.See", Position = SECONDARY, Inputs = { Enum.KeyCode.Q, Enum.KeyCode.ButtonX } },
	{ Id = "RoleDash", Role = "Bodyguard", Ability = "Dash", TitleKey = "Ability.Dash", Position = SECONDARY, Inputs = { Enum.KeyCode.Q, Enum.KeyCode.ButtonX } },
	{ Id = "RoleBless", Role = "Monk", Ability = "Bless", TitleKey = "Ability.Bless", Position = SECONDARY, Inputs = { Enum.KeyCode.Q, Enum.KeyCode.ButtonX } },
	{ Id = "RoleFlashlight", Role = "Villager", Ability = "Flashlight", TitleKey = "Ability.Flashlight", Position = SECONDARY, Inputs = { Enum.KeyCode.F, Enum.KeyCode.ButtonY } },
}

local RoleController = {}

local localPlayer = Players.LocalPlayer
local bound: { [string]: boolean } = {}
local usesLeft: { [string]: number } = {}
local readyAt: { [string]: number } = {}
local roster: { { Id: number, Name: string, Alive: boolean } } = {}

local pickerGui: ScreenGui
local pickerList: Instance
local optionTemplate: TextButton

--------------------------------------------------------------------------------
-- Picker (Monk)
--------------------------------------------------------------------------------

local function closePicker()
	pickerGui.Enabled = false
end

local function openPicker()
	for _, child in pickerList:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for order, entry in roster do
		if entry.Alive then
			local option = optionTemplate:Clone()
			option.LayoutOrder = order
			option.Text = if entry.Id == localPlayer.UserId
				then Loc.format("Picker.You", { name = entry.Name })
				else entry.Name
			option.Visible = true
			option.Parent = pickerList
			option.Activated:Connect(function()
				Remotes.get("AbilityUse"):FireServer("Bless", entry.Id)
				closePicker()
			end)
		end
	end
	pickerGui.Enabled = true
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

local function title(action: Action): string
	local text = Loc.format(action.TitleKey)
	local ready = readyAt[action.Ability]
	if ready then
		local left = ready - workspace:GetServerTimeNow()
		if left > 0 then
			return string.format("%s %d", text, math.ceil(left))
		end
	end
	local remaining = usesLeft[action.Ability]
	if remaining then
		return string.format("%s (%d)", text, remaining)
	end
	return text
end

local function activate(action: Action, fromTouch: boolean)
	if action.Ability == "Bless" then
		openPicker()
	elseif action.Ability == "Shoot" then
		local direction = Aim.direction(Config.Abilities.Sheriff.Range, fromTouch)
		if direction then
			Remotes.get("AbilityUse"):FireServer("Shoot", direction)
		end
	else
		Remotes.get("AbilityUse"):FireServer(action.Ability)
	end
end

local function bind(action: Action)
	if bound[action.Id] then
		return
	end
	bound[action.Id] = true
	ContextActionService:BindAction(action.Id, function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			-- A tap on the touch button: aim at the middle of the screen.
			activate(action, input.UserInputType == Enum.UserInputType.Touch)
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
	local usable = ClientState.Form == "Human" and ClientState.Alive
	for _, action in ACTIONS do
		if usable and action.Role == ClientState.Role then
			bind(action)
		else
			unbind(action)
		end
	end
	if not usable then
		closePicker()
	end
end

--------------------------------------------------------------------------------
-- Dash: the server says go, this client moves its own character
--------------------------------------------------------------------------------

local function startDash(data: any)
	if type(data) ~= "table" or typeof(data.Direction) ~= "Vector3" then
		return
	end
	local speed = if type(data.Speed) == "number" then data.Speed else 0
	local duration = if type(data.Duration) == "number" then data.Duration else 0
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or duration <= 0 then
		return
	end
	local velocity = data.Direction * speed
	local endsAt = os.clock() + duration
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if os.clock() >= endsAt or not root.Parent then
			connection:Disconnect()
			return
		end
		local current = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, current.Y, velocity.Z)
	end)
end

function RoleController.Start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	pickerGui = playerGui:WaitForChild("PickerUI") :: ScreenGui
	local panel = pickerGui:WaitForChild("Panel")
	pickerList = panel:WaitForChild("List")
	optionTemplate = pickerGui:WaitForChild("Templates"):WaitForChild("Option") :: TextButton
	local closeButton = panel:WaitForChild("CloseButton") :: TextButton;
	(panel:WaitForChild("Title") :: TextLabel).Text = Loc.format("Picker.Bless")
	closeButton.Text = Loc.format("Picker.Close")
	closeButton.Activated:Connect(closePicker)

	Remotes.get("RoleAssigned").OnClientEvent:Connect(function(roleId: any)
		if type(roleId) == "string" then
			ClientState.set("Role", roleId)
		end
	end)
	Remotes.get("RosterChanged").OnClientEvent:Connect(function(list: any)
		if type(list) ~= "table" then
			return
		end
		roster = {}
		for _, entry in list do
			if type(entry) == "table" and type(entry.Id) == "number" and type(entry.Name) == "string" then
				table.insert(roster, { Id = entry.Id, Name = entry.Name, Alive = entry.Alive == true })
				if entry.Id == localPlayer.UserId then
					ClientState.set("Alive", entry.Alive == true)
				end
			end
		end
	end)
	Remotes.get("AbilityState").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" or type(data.Name) ~= "string" then
			return
		end
		if type(data.UsesLeft) == "number" then
			usesLeft[data.Name] = data.UsesLeft
		end
		if type(data.ReadyAt) == "number" then
			readyAt[data.Name] = data.ReadyAt
		end
	end)
	Remotes.get("DashStart").OnClientEvent:Connect(startDash)
	ClientState.Changed:Connect(refresh)

	-- Uses left / cooldown seconds on the buttons.
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

return RoleController
