--!strict
--[[
	ItemController — using items (GDD §11). Each item is a Tool in the Backpack
	(made by the server), so the hotbar works on PC, mobile and console.
	Activating a tool only sends "use item X, aimed here"; the server decides.
	The hotbar is hidden while hiding or dead. In monster form it stays: the
	server has put the items away and the monster's skills are on it
	(owner, 23 Nov 2026; WolfService / WolfController).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Shared.Config)
local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Aim = require(script.Parent.Aim)
local ClientState = require(script.Parent.ClientState)

local AIMED: { [string]: number } = {
	Gun = Config.Items.Gun.Range,
	Axe = Config.Items.Axe.ThrowRange,
}

local ItemController = {}

local localPlayer = Players.LocalPlayer
local hooked: { [Tool]: boolean } = {}

local function hook(tool: Instance)
	if not tool:IsA("Tool") or hooked[tool] then
		return
	end
	local kind = tool:GetAttribute("Kind")
	local itemId = tool:GetAttribute("ItemId")
	if type(kind) ~= "string" or type(itemId) ~= "string" then
		return
	end
	hooked[tool] = true
	-- Local display only: the server finds items by ItemId, not by name.
	tool.Name = Loc.format("Item." .. kind .. ".Name")
	tool.ToolTip = Loc.format("Item." .. kind .. ".Desc")
	tool.Activated:Connect(function()
		local range = AIMED[kind]
		local aim = if range then Aim.direction(range) else nil
		Remotes.get("ItemUse"):FireServer(itemId, aim)
	end)
	tool.Destroying:Connect(function()
		hooked[tool] = nil
	end)
end

-- Gear with a cooldown (smoke bomb, bear trap): the seconds left after the name.
local function refreshCooldowns()
	local now = workspace:GetServerTimeNow()
	for tool in hooked do
		local kind = tool:GetAttribute("Kind")
		local readyAt = tool:GetAttribute("ReadyAt")
		if type(kind) == "string" and type(readyAt) == "number" then
			local text = Loc.format("Item." .. kind .. ".Name")
			local left = readyAt - now
			local wanted = if left > 0 then string.format("%s %d", text, math.ceil(left)) else text
			if tool.Name ~= wanted then
				tool.Name = wanted -- only on this screen
			end
		end
	end
end

local function watch(container: Instance)
	container.ChildAdded:Connect(hook)
	for _, child in container:GetChildren() do
		hook(child)
	end
end

local function refreshHotbar()
	local usable = ClientState.Alive and not ClientState.Hidden
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, usable)
	if not usable then
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
		end
	end
end

function ItemController.Start()
	-- Every respawn brings a new Backpack (and the server refills it).
	localPlayer.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then
			watch(child)
		end
	end)
	watch(localPlayer:WaitForChild("Backpack"))
	localPlayer.CharacterAdded:Connect(function(character: Model)
		watch(character) -- an equipped tool moves into the character
	end)
	if localPlayer.Character then
		watch(localPlayer.Character)
	end
	ClientState.Changed:Connect(refreshHotbar)
	refreshHotbar()
	task.spawn(function()
		while true do
			refreshCooldowns()
			task.wait(0.25)
		end
	end)
end

return ItemController
