--!strict
--[[
	InventoryService — items (GDD §11) and the forest crate (GDD §6.1).

	The server owns every inventory. Each item a player holds is also a Roblox
	Tool in their Backpack, which gives a hotbar on PC, mobile and console for
	free. Activating a Tool only sends "use item X (aimed here)"; the server
	decides what happens.

	  Shovel      melee stun 3 s, used up when it hits
	  Apple       +30% speed for 5 s, eaten
	  Axe         thrown forward, stun 5 s, 2 throws (a miss still counts)
	  Gun         like the Sheriff's: 1 shot per day / night; max one per
	              player; the Killer can never hold one
	  First aid   heal to full, used up (the Doctor can spend it on a revive)
	  Cross       blocks one attack while carried, then breaks
	  Flashlight  light on / off

	Dropping: on death the items fall where the body lies (and stay); an
	exiled player's items are scattered in the forest; a player who leaves
	leaves them in a pile at the plaza. Role abilities are not items, so they
	never drop.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Zones = require(ReplicatedStorage.Shared.Zones)

local Logic = script.Parent.Parent.Logic
local AbilityUses = require(Logic.AbilityUses)
local Loot = require(Logic.Loot)
local Roster = require(Logic.Roster)

local CombatService = require(script.Parent.CombatService)
local Flashlight = require(script.Parent.Flashlight)
local HidingService = require(script.Parent.HidingService)
local MatchService = require(script.Parent.MatchService)
local Melee = require(script.Parent.Melee)
local MoveService = require(script.Parent.MoveService)
local Net = require(script.Parent.Net)
local ProfileService = require(script.Parent.ProfileService)
local Prompts = require(script.Parent.Prompts)
local RoleService = require(script.Parent.RoleService)
local RoundService = require(script.Parent.RoundService)
local Sight = require(script.Parent.Sight)
local WolfService = require(script.Parent.WolfService)

export type Item = {
	Id: string,
	Kind: string,
	Uses: number,
}

local Items = Config.Items
local REACH_SLACK = 4
local THROW_HEIGHT = 1.5
local SHIELD_CAUSES = { Wolf = true, Pup = true, Killer = true, Sheriff = true }

local InventoryService = {}

local inventories: { [number]: { Item } } = {}
local nextId = 0
local appleTokens: { [number]: number } = {}
local uses = AbilityUses.new() -- gun shots per day / night
local rng = Rng.wrap(Random.new())
local worldFolder: Folder

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

function InventoryService.Items(id: number): { Item }
	return inventories[id] or {}
end

function InventoryService.Count(id: number, kind: string): number
	local count = 0
	for _, item in InventoryService.Items(id) do
		if item.Kind == kind then
			count += 1
		end
	end
	return count
end

-- May this member pick up / receive an item of `kind`?
function InventoryService.CanTake(id: number, kind: string): boolean
	local member = MatchService.Roster.Members[id]
	if not member or not member.Alive then
		return false
	end
	if kind == "Gun" then
		return Loot.canHoldGun(member.Role, InventoryService.Count(id, "Gun"))
	end
	return Items[kind] ~= nil
end

local function startUses(kind: string): number
	local cfg = (Items :: any)[kind]
	return if cfg and type(cfg.Uses) == "number" then cfg.Uses else 1
end

--------------------------------------------------------------------------------
-- Tools (what the player sees in their hotbar)
--------------------------------------------------------------------------------

local function backpackOf(id: number): Instance?
	local player = MatchService.PlayerOf(id)
	return if player then player:FindFirstChildOfClass("Backpack") else nil
end

local function findTool(id: number, itemId: string): Tool?
	local player = MatchService.PlayerOf(id)
	if not player then
		return nil
	end
	local holders: { Instance } = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		table.insert(holders, backpack)
	end
	if player.Character then
		table.insert(holders, player.Character) -- an equipped tool lives in the character
	end
	for _, holder in holders do
		do
			for _, child in holder:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("ItemId") == itemId then
					return child
				end
			end
		end
	end
	return nil
end

local function makeTool(item: Item, ownerId: number): Tool
	local look = (Config.ItemLook :: any)[item.Kind]
	local tool = Instance.new("Tool")
	tool.Name = item.Kind -- the client shows the translated name
	tool.CanBeDropped = false -- dropping is decided by the game, not the Backspace key
	tool.RequiresHandle = true
	tool:SetAttribute("ItemId", item.Id)
	tool:SetAttribute("Kind", item.Kind)
	tool:SetAttribute("Uses", item.Uses)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = if look then look.Size else Vector3.new(0.6, 0.6, 0.6)
	handle.Color = if look then look.Color else Color3.new(1, 1, 1)
	if item.Kind == "Gun" and ProfileService.Skin(MatchService.PlayerOf(ownerId), "Gun") then
		handle.Color = RoleService.SkinColor(ownerId, "Gun") -- cosmetic gun skin
	end
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	return tool
end

--------------------------------------------------------------------------------
-- Give / remove
--------------------------------------------------------------------------------

function InventoryService.Give(id: number, kind: string, itemUses: number?): Item?
	if not InventoryService.CanTake(id, kind) then
		return nil
	end
	nextId += 1
	local item: Item = { Id = "item" .. nextId, Kind = kind, Uses = itemUses or startUses(kind) }
	local list = inventories[id]
	if not list then
		list = {}
		inventories[id] = list
	end
	table.insert(list, item)
	local backpack = backpackOf(id)
	if backpack then
		makeTool(item, id).Parent = backpack
	end
	local player = MatchService.PlayerOf(id)
	if player then
		Net.fire(player, "Effect", { Kind = "Gained", Item = kind })
	end
	return item
end

local function find(id: number, itemId: string): Item?
	for _, item in InventoryService.Items(id) do
		if item.Id == itemId then
			return item
		end
	end
	return nil
end

function InventoryService.Remove(id: number, itemId: string)
	local list = inventories[id]
	if not list then
		return
	end
	for index, item in list do
		if item.Id == itemId then
			table.remove(list, index)
			break
		end
	end
	local tool = findTool(id, itemId)
	if tool then
		tool:Destroy()
	end
end

-- Uses one charge of an item; removes it when none are left.
local function spend(id: number, item: Item)
	item.Uses -= 1
	if item.Uses <= 0 then
		InventoryService.Remove(id, item.Id)
	else
		local tool = findTool(id, item.Id)
		if tool then
			tool:SetAttribute("Uses", item.Uses)
		end
	end
end

-- Removes one item of `kind` (e.g. a First aid for the Doctor). Returns whether one was there.
function InventoryService.Consume(id: number, kind: string): boolean
	for _, item in InventoryService.Items(id) do
		if item.Kind == kind then
			spend(id, item)
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Items on the ground
--------------------------------------------------------------------------------

local function onPickup(player: Player, model: Model, prompt: ProximityPrompt)
	local member = MatchService.MemberOf(player)
	if not member or not member.Alive or WolfService.IsTransformed(member.Id) or HidingService.IsHidden(member.Id) then
		return
	end
	if not model.Parent then
		return -- someone else was faster
	end
	local kind = model:GetAttribute("Kind")
	local itemUses = model:GetAttribute("Uses")
	local root = MatchService.RootOf(member.Id)
	local part = model.PrimaryPart
	if type(kind) ~= "string" or not root or not part then
		return
	end
	if (root.CFrame.Position - part.CFrame.Position).Magnitude > prompt.MaxActivationDistance + REACH_SLACK then
		return
	end
	if not InventoryService.CanTake(member.Id, kind) then
		return
	end
	model:Destroy()
	InventoryService.Give(member.Id, kind, if type(itemUses) == "number" then itemUses else nil)
end

function InventoryService.SpawnWorldItem(kind: string, itemUses: number, position: Vector3): Model
	local look = (Config.ItemLook :: any)[kind]
	local model = Instance.new("Model")
	model.Name = kind
	local part = Instance.new("Part")
	part.Name = "Item"
	part.Size = if look then look.Size else Vector3.new(0.6, 0.6, 0.6)
	part.Color = if look then look.Color else Color3.new(1, 1, 1)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CFrame = CFrame.new(position + Vector3.new(0, part.Size.Y / 2 + 0.2, 0))
	part.Parent = model
	model.PrimaryPart = part
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Uses", itemUses)
	model:AddTag("WorldItem")
	local prompt = Prompts.create(part, "PickupPrompt", "Prompt.PickUp", Items.PickupHold)
	prompt.ObjectText = kind
	prompt:SetAttribute("Audience", "Human")
	prompt:SetAttribute("Active", true)
	prompt:SetAttribute("ItemKind", kind)
	prompt.Enabled = true
	prompt.Triggered:Connect(function(player: Player)
		onPickup(player, model, prompt)
	end)
	model.Parent = worldFolder
	return model
end

local function ground(position: Vector3): Vector3
	return Vector3.new(position.X, 0, position.Z)
end

-- Places `count` drops in a small circle around `centre`.
local function spread(centre: Vector3, index: number, count: number): Vector3
	if count <= 1 then
		return centre
	end
	local angle = (index / count) * math.pi * 2
	local radius = Items.DropSpread
	return centre + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function forestPoint(): Vector3
	local inner = Config.Map.FenceRadius + 10
	local outer = Config.Map.ForestOuterRadius - 12
	local radius = math.sqrt(inner * inner + rng:NextNumber() * (outer * outer - inner * inner))
	local angle = rng:NextNumber() * math.pi * 2
	return Vector3.new(math.sin(angle) * radius, 0, -math.cos(angle) * radius)
end

local function plazaPile(): Vector3
	local map = workspace:FindFirstChild("Map")
	local markers = map and map:FindFirstChild("Markers")
	local pile = markers and markers:FindFirstChild("ItemPile")
	if pile and pile:IsA("Attachment") then
		return ground(Zones.worldCFrame(pile).Position)
	end
	return Vector3.new(0, 0, 0)
end

-- Drops everything a member carries (GDD §11).
function InventoryService.DropAll(id: number, how: string, where: Vector3?)
	local list = inventories[id]
	inventories[id] = nil
	if not list or #list == 0 then
		return
	end
	local centre = if how == "Left" then plazaPile() else ground(where or plazaPile())
	for index, item in list do
		local tool = findTool(id, item.Id)
		if tool then
			tool:Destroy()
		end
		local position = if how == "Exile" then forestPoint() else spread(centre, index, #list)
		InventoryService.SpawnWorldItem(item.Kind, item.Uses, position)
	end
end

--------------------------------------------------------------------------------
-- Using items
--------------------------------------------------------------------------------

local function scope(): string?
	local state = RoundService.State
	if state.Phase == "Night" then
		return "Night:" .. state.Night
	elseif state.Phase == "Day" or state.Phase == "MeetingCountdown" then
		return "Day:" .. state.Day
	end
	return nil -- no fighting during the meeting or the full-moon warning
end

local function isDirection(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and value.Magnitude > 1e-3
		and value.Magnitude < 1e6
end

local function eatApple(id: number, item: Item)
	local cfg = Items.Apple
	local token = (appleTokens[id] or 0) + 1
	appleTokens[id] = token
	MoveService.SetModifier(id, "Apple", { Multiplier = 1 + cfg.SpeedBonus })
	task.delay(cfg.Duration, function()
		if appleTokens[id] == token then
			MoveService.ClearModifier(id, "Apple")
		end
	end)
	spend(id, item)
end

local function throwAxe(id: number, item: Item, aim: Vector3)
	local root = MatchService.RootOf(id)
	if not root then
		return
	end
	local cfg = Items.Axe
	local origin = root.CFrame.Position + Vector3.new(0, THROW_HEIGHT, 0)
	local ray = aim.Unit * cfg.ThrowRange
	local hitId = Sight.firstBody(origin, ray, MatchService.CharacterOf(id))
	local hitRoot = if hitId then MatchService.RootOf(hitId) else nil
	local landing = if hitRoot then hitRoot.CFrame.Position else origin + ray * (Sight.clearDistance(origin, ray) / cfg.ThrowRange)
	Net.fireAll("Effect", { Kind = "Throw", From = origin, To = landing, Speed = cfg.ThrowSpeed })
	spend(id, item) -- a throw is a use, hit or miss (GDD §11)
	if hitId then
		CombatService.Stun(hitId, cfg.StunDuration)
	end
end

local function swingShovel(id: number, item: Item)
	local target = Melee.findTarget(id, Items.Shovel.Range, Items.MinDot, function()
		return true
	end)
	if target then
		CombatService.Stun(target.Id, Items.Shovel.StunDuration)
		spend(id, item)
	end
end

local function fireGun(id: number, aim: Vector3)
	local phaseScope = scope()
	if not phaseScope then
		return
	end
	if AbilityUses.tryUse(uses, id, "GunItem", phaseScope, Items.Gun.ShotsPerPhase) then
		RoleService.FireGun(id, aim)
	end
end

local function onUse(player: Player, itemId: any, aim: any)
	local member = MatchService.MemberOf(player)
	if not member or not member.Alive or type(itemId) ~= "string" or MatchService.Winner then
		return
	end
	local id = member.Id
	-- A werewolf has paws, a hidden player is parked away, a stunned one cannot act.
	if WolfService.IsTransformed(id) or HidingService.IsHidden(id) or CombatService.IsStunned(id) then
		return
	end
	local item = find(id, itemId)
	if not item then
		return
	end
	local kind = item.Kind
	if kind == "Apple" then
		eatApple(id, item)
	elseif kind == "FirstAid" then
		CombatService.Heal(id)
		spend(id, item)
	elseif kind == "Flashlight" then
		local character = MatchService.CharacterOf(id)
		if character then
			Flashlight.toggle(character)
		end
	elseif kind == "Cross" then
		Net.fire(player, "Effect", { Kind = "CrossInfo" }) -- passive: nothing to do
	elseif kind == "Gun" then
		if isDirection(aim) then
			fireGun(id, aim)
		end
	elseif kind == "Axe" then
		if isDirection(aim) and scope() then
			throwAxe(id, item, aim)
		end
	elseif kind == "Shovel" then
		if scope() then
			swingShovel(id, item)
		end
	end
end

--------------------------------------------------------------------------------
-- Crate
--------------------------------------------------------------------------------

local function onOpenCrate(player: Player, crate: Model, prompt: ProximityPrompt)
	local member = MatchService.MemberOf(player)
	if not member or not member.Alive or WolfService.IsTransformed(member.Id) or not crate.Parent then
		return
	end
	local root = MatchService.RootOf(member.Id)
	local part = crate.PrimaryPart
	if not root or not part then
		return
	end
	if (root.CFrame.Position - part.CFrame.Position).Magnitude > prompt.MaxActivationDistance + REACH_SLACK then
		return
	end
	local position = ground(part.CFrame.Position)
	crate:Destroy()
	local kind = Loot.rollCrate(rng)
	if not InventoryService.Give(member.Id, kind) then
		-- e.g. a gun for the Killer: it stays on the ground for someone else.
		InventoryService.SpawnWorldItem(kind, startUses(kind), position + Vector3.new(Items.DropSpread, 0, 0))
	end
end

function InventoryService.SpawnCrate(position: Vector3): Model
	local look = Config.CrateLook
	local crate = Instance.new("Model")
	crate.Name = "Crate"
	local box = Instance.new("Part")
	box.Name = "Box"
	box.Size = look.Size
	box.Color = look.Color
	box.Material = Enum.Material.WoodPlanks
	box.Anchored = true
	box.CFrame = CFrame.new(position + Vector3.new(0, look.Size.Y / 2, 0))
	box.Parent = crate
	crate.PrimaryPart = box
	crate:AddTag("Crate")
	local prompt = Prompts.create(box, "OpenPrompt", "Prompt.OpenCrate", Config.Crate.OpenHold)
	prompt:SetAttribute("Audience", "Human")
	prompt:SetAttribute("Active", true)
	prompt.Enabled = true
	prompt.Triggered:Connect(function(player: Player)
		onOpenCrate(player, crate, prompt)
	end)
	crate.Parent = worldFolder
	return crate
end

-- Every morning: a 30% chance that one crate appears under a random forest tree.
local function maybeSpawnCrate()
	if not Loot.shouldSpawnCrate(rng) then
		return
	end
	local spots: { Vector3 } = {}
	for _, tree in CollectionService:GetTagged("TaskTree") do
		local trunk = if tree:IsA("Model") then tree.PrimaryPart else nil
		local spot = trunk and trunk:FindFirstChild("CrateSpot")
		if spot and spot:IsA("Attachment") then
			table.insert(spots, ground(Zones.worldCFrame(spot).Position))
		end
	end
	if #spots > 0 then
		InventoryService.SpawnCrate(Rng.pick(spots, rng))
	end
end

--------------------------------------------------------------------------------

function InventoryService.Init()
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "Items"
	worldFolder.Parent = workspace
end

function InventoryService.Start()
	Net.on("ItemUse", onUse, 12, 5)

	-- The Cross blocks one attack while carried (after a blessing, if any).
	CombatService.AddShield(function(victimId: number, cause: Roster.DeathCause): boolean
		if SHIELD_CAUSES[cause] and InventoryService.Count(victimId, "Cross") > 0 then
			InventoryService.Consume(victimId, "Cross")
			return true
		end
		return false
	end)

	-- A First aid lets the Doctor revive one more body (GDD §9).
	RoleService.ConsumeExtraRevive = function(doctorId: number): boolean
		return InventoryService.Consume(doctorId, "FirstAid")
	end

	-- A new body (respawn in place) comes with a new, empty Backpack: Roblox
	-- throws the old tools away, so the hotbar is rebuilt from the inventory.
	MatchService.BodyReplaced:Connect(function(member: Roster.Member)
		local player = MatchService.PlayerOf(member.Id)
		if not player then
			return
		end
		local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
		if not backpack then
			return
		end
		for _, item in InventoryService.Items(member.Id) do
			if not findTool(member.Id, item.Id) then
				makeTool(item, member.Id).Parent = backpack
			end
		end
	end)

	MatchService.MemberDied:Connect(function(member: Roster.Member, cause: Roster.DeathCause)
		local root = MatchService.RootOf(member.Id)
		local body = MatchService.BodyOf(member.Id)
		local bodyRoot = body and body:FindFirstChild("HumanoidRootPart")
		local where = if root
			then root.CFrame.Position
			elseif bodyRoot and bodyRoot:IsA("BasePart") then bodyRoot.CFrame.Position
			else nil
		InventoryService.DropAll(member.Id, if cause == "Exile" or cause == "Left" then cause else "Death", where)
		appleTokens[member.Id] = nil
	end)

	RoundService.PhaseStarted:Connect(function(state: PhaseMachine.PhaseState)
		if state.Phase == "Day" then
			maybeSpawnCrate()
		end
	end)
end

return InventoryService
