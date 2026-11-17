--!strict
--[[
	HouseService — houses and doors (GDD §6.1, §6.3, §6.4).

	Night  : everyone in the village is warped into a random house (one each)
	         and every door shuts. The wolf side appears at the plaza centre.
	         Only the occupant can open the door, and it then stays open.
	Morning: survivors in the village are warped to the front of the house
	         they had; doors broken in the night show repair marks.

	A player's house is secret: it is sent to that player only.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Zones = require(ReplicatedStorage.Shared.Zones)

local Logic = script.Parent.Parent.Logic
local DoorState = require(Logic.DoorState)
local NightHousing = require(Logic.NightHousing)
local Roster = require(Logic.Roster)

local MatchService = require(script.Parent.MatchService)
local Net = require(script.Parent.Net)
local Prompts = require(script.Parent.Prompts)
local RoundService = require(script.Parent.RoundService)

type House = {
	Id: number,
	Model: Model,
	Zone: BasePart,
	Door: BasePart,
	State: DoorState.Door,
	ClosedCFrame: CFrame,
	OpenCFrame: CFrame,
	InsideSpawn: Attachment,
	FrontSpawn: Attachment,
	OpenPrompt: ProximityPrompt,
	DebugPrompt: ProximityPrompt?,
}

local HouseService = {}

-- memberId -> houseId for the current / last night.
HouseService.Assigned = {} :: { [number]: number }
HouseService.DoorChanged = Signal.new() -- (houseId, door state)

local houses: { [number]: House } = {}
local houseCount = 0
local rng = Rng.wrap(Random.new())
local openTween = TweenInfo.new(Config.Door.OpenTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--------------------------------------------------------------------------------
-- Door visuals (server side, so every client sees the same door)
--------------------------------------------------------------------------------

local function setGuiEnabled(door: BasePart, name: string, enabled: boolean)
	local gui = door:FindFirstChild(name)
	if gui and gui:IsA("LayerCollector") then
		gui.Enabled = enabled
	end
end

local function applyDoor(house: House, animate: boolean)
	local state = house.State
	local door = house.Door
	local isNight = RoundService.IsNight()

	door:SetAttribute("HP", state.HP)
	door:SetAttribute("MaxHP", state.MaxHP)
	door:SetAttribute("State", state.State)
	door:SetAttribute("Reinforced", state.Reinforced)
	-- A reinforced door looks armoured (GDD §9 Engineer).
	door.Material = if state.Reinforced then Enum.Material.DiamondPlate else Enum.Material.WoodPlanks

	if state.State == "Broken" then
		door.Transparency = 1
		door.CanCollide = false
	else
		door.Transparency = 0
		door.CanCollide = true
		local goal = if state.State == "Open" then house.OpenCFrame else house.ClosedCFrame
		if animate then
			TweenService:Create(door, openTween, { CFrame = goal }):Play()
		else
			door.CFrame = goal
		end
	end

	-- HP bar: visible on closed doors during the night.
	local showBar = isNight and state.State == "Closed"
	setGuiEnabled(door, "HPBar", showBar)
	local bar = door:FindFirstChild("HPBar")
	local fill = bar and bar:FindFirstChild("Fill", true)
	if fill and fill:IsA("Frame") then
		fill.Size = UDim2.fromScale(math.clamp(state.HP / state.MaxHP, 0, 1), 1)
	end

	local showRepair = state.RepairLook and state.State ~= "Broken"
	setGuiEnabled(door, "RepairFront", showRepair)
	setGuiEnabled(door, "RepairBack", showRepair)

	-- "Active" mirrors Enabled for clients, which hide other people's door
	-- prompts locally (see PromptController).
	local canOpen = state.State == "Closed" and (isNight or Config.Door.UsableByDay)
	house.OpenPrompt:SetAttribute("Active", canOpen)
	house.OpenPrompt.Enabled = canOpen
	if house.DebugPrompt then
		house.DebugPrompt.Enabled = isNight and state.State == "Closed"
	end
	HouseService.DoorChanged:Fire(house.Id, state)
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

function HouseService.Count(): number
	return houseCount
end

-- Which house interior contains this position (nil = outdoors).
function HouseService.HouseAt(position: Vector3): number?
	for id, house in houses do
		if Zones.isInsideBox(house.Zone.CFrame, house.Zone.Size, position) then
			return id
		end
	end
	return nil
end

function HouseService.DoorOf(houseId: number): DoorState.Door?
	local house = houses[houseId]
	return if house then house.State else nil
end

--------------------------------------------------------------------------------
-- Door actions
--------------------------------------------------------------------------------

-- Wolf / pup hit (milestone 3). Returns true if the door broke.
function HouseService.DamageDoor(houseId: number, amount: number): boolean
	local house = houses[houseId]
	if not house or not RoundService.IsNight() then
		return false
	end
	local broke = DoorState.damage(house.State, amount)
	applyDoor(house, false)
	return broke
end

-- A wolf swings at whatever is in front of it: finds the closest closed door
-- within reach and damages it. Returns the house id that was hit, if any.
function HouseService.HitDoorNear(position: Vector3, look: Vector3, range: number, amount: number): number?
	local bestId: number? = nil
	local bestDistance = range
	for id, house in houses do
		if house.State.State == "Closed" then
			local offset = house.Door.CFrame.Position - position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local distance = flat.Magnitude
			local facing = distance < 1 or flat.Unit:Dot(look) >= 0
			if distance <= bestDistance and facing then
				bestId = id
				bestDistance = distance
			end
		end
	end
	if bestId then
		HouseService.DamageDoor(bestId, amount)
	end
	return bestId
end

-- Houses whose door was broken last night and still shows the repair marks.
function HouseService.DoorsNeedingRepair(): { number }
	local ids: { number } = {}
	for id, house in houses do
		if house.State.RepairLook then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- Task "repair a broken door" (GDD §10). Returns false if there was nothing to repair.
function HouseService.RepairDoor(houseId: number): boolean
	local house = houses[houseId]
	if not house or not DoorState.repair(house.State) then
		return false
	end
	applyDoor(house, false)
	return true
end

-- Engineer ability (milestone 4).
function HouseService.ReinforceDoor(houseId: number): boolean
	local house = houses[houseId]
	if not house or not DoorState.reinforce(house.State) then
		return false
	end
	applyDoor(house, false)
	return true
end

local function onOpenPrompt(player: Player, house: House)
	local member = MatchService.MemberOf(player)
	if not member or not member.Alive or Roster.isWolfSide(member) then
		return
	end
	if not (RoundService.IsNight() or Config.Door.UsableByDay) then
		return
	end
	-- Only the occupant of this house may open it.
	if RoundService.IsNight() and HouseService.Assigned[member.Id] ~= house.Id then
		return
	end
	local root = MatchService.RootOf(member.Id)
	if not root or (root.CFrame.Position - house.Door.CFrame.Position).Magnitude > Config.Human.InteractDistance + 4 then
		return
	end
	if DoorState.open(house.State) then
		applyDoor(house, true)
	end
end

--------------------------------------------------------------------------------
-- Night / morning
--------------------------------------------------------------------------------

local function marker(name: string): Attachment?
	local map = workspace:FindFirstChild("Map")
	local markers = map and map:FindFirstChild("Markers")
	local found = markers and markers:FindFirstChild(name)
	return if found and found:IsA("Attachment") then found else nil
end

local function warp(memberId: number, target: CFrame)
	local character = MatchService.CharacterOf(memberId)
	if character then
		character:PivotTo(target)
	end
end

local function beginNight()
	for _, house in houses do
		DoorState.beginNight(house.State)
		applyDoor(house, false)
	end

	-- Everyone in the village gets a house. Players in the forest stay there.
	-- The wolf side always gets one too (their morning spot), but appears at the plaza.
	local roster = MatchService.Roster
	local ids: { number } = {}
	for _, member in Roster.alive(roster) do
		local root = MatchService.RootOf(member.Id)
		if member.IsBot or Roster.isWolfSide(member) or (root and Zones.isVillage(root.CFrame.Position)) then
			table.insert(ids, member.Id)
		end
	end
	HouseService.Assigned = NightHousing.assign(ids, houseCount, rng)

	for _, member in Roster.alive(roster) do
		local houseId = HouseService.Assigned[member.Id]
		local house = if houseId then houses[houseId] else nil
		local isWolfSide = Roster.isWolfSide(member)
		if isWolfSide then
			local spawn = marker(if member.IsPup then "PupSpawn" else "WolfSpawn")
			if spawn then
				warp(member.Id, Zones.worldCFrame(spawn))
			end
		elseif house then
			warp(member.Id, Zones.worldCFrame(house.InsideSpawn))
		end
		local player = MatchService.PlayerOf(member.Id)
		if player then
			-- 0 = no door of your own tonight (forest, or wolf side).
			Net.fire(player, "HouseAssigned", if house and not isWolfSide then house.Id else 0)
		end
	end
end

local function beginDay(state: PhaseMachine.PhaseState)
	if state.Day <= 1 then
		return
	end
	for _, house in houses do
		DoorState.beginDay(house.State)
		applyDoor(house, false)
	end
	-- Survivors still in the village wake up in front of their house.
	for _, member in Roster.alive(MatchService.Roster) do
		local houseId = HouseService.Assigned[member.Id]
		local house = if houseId then houses[houseId] else nil
		local root = MatchService.RootOf(member.Id)
		if house and root and Zones.isVillage(root.CFrame.Position) then
			warp(member.Id, Zones.worldCFrame(house.FrontSpawn))
		end
	end
end

--------------------------------------------------------------------------------

local function register(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local id = model:GetAttribute("HouseId")
	local floor = model:FindFirstChild("Floor")
	local zone = model:FindFirstChild("InteriorZone")
	local door = model:FindFirstChild("Door")
	local inside = floor and floor:FindFirstChild("InsideSpawn")
	local front = floor and floor:FindFirstChild("FrontSpawn")
	if
		type(id) ~= "number"
		or not (zone and zone:IsA("BasePart"))
		or not (door and door:IsA("BasePart"))
		or not (inside and inside:IsA("Attachment"))
		or not (front and front:IsA("Attachment"))
	then
		warn(`[HouseService] {model:GetFullName()} is not a valid house; rebuild the map`)
		return
	end

	local closed = door:GetAttribute("ClosedCFrame")
	local open = door:GetAttribute("OpenCFrame")
	local anchor = door:FindFirstChild("PromptAnchor") or door

	local house: House = {
		Id = id,
		Model = model,
		Zone = zone,
		Door = door,
		State = DoorState.new(),
		ClosedCFrame = if typeof(closed) == "CFrame" then closed else door.CFrame,
		OpenCFrame = if typeof(open) == "CFrame" then open else door.CFrame,
		InsideSpawn = inside,
		FrontSpawn = front,
		OpenPrompt = Prompts.create(anchor, "OpenPrompt", "Prompt.OpenDoor", Config.Door.OpenHold),
		DebugPrompt = nil,
	}
	house.OpenPrompt:SetAttribute("HouseId", id)
	house.OpenPrompt:SetAttribute("Audience", "Owner") -- shown to the occupant only
	house.OpenPrompt.Triggered:Connect(function(player: Player)
		onOpenPrompt(player, house)
	end)

	if Config.Debug.Enabled and Config.Debug.DoorHitPrompt then
		local debugPrompt = Prompts.create(anchor, "DebugHitPrompt", "Prompt.DebugHitDoor", 0)
		debugPrompt.KeyboardKeyCode = Enum.KeyCode.G
		debugPrompt.UIOffset = Vector2.new(0, 80)
		debugPrompt.Triggered:Connect(function()
			HouseService.DamageDoor(id, Config.Wolf.DoorDamage)
		end)
		house.DebugPrompt = debugPrompt
	end

	houses[id] = house
	houseCount += 1
	applyDoor(house, false) -- every door attribute exists from the start
end

function HouseService.Init()
	for _, model in CollectionService:GetTagged("House") do
		register(model)
	end
	if houseCount == 0 then
		warn("[HouseService] no houses found: run build/BuildVillage.luau in Studio")
	end
end

function HouseService.Start()
	RoundService.PhaseStarted:Connect(function(state: PhaseMachine.PhaseState)
		if state.Phase == "Night" then
			beginNight()
		elseif state.Phase == "Day" then
			beginDay(state)
		end
	end)
	RoundService.PhaseEnded:Connect(function(state: PhaseMachine.PhaseState)
		if state.Phase == "Night" then
			-- Hide HP bars / prompts as soon as the night is over.
			task.defer(function()
				for _, house in houses do
					applyDoor(house, false)
				end
			end)
		end
	end)
	MatchService.SyncRequested:Connect(function(player: Player)
		local member = MatchService.MemberOf(player)
		if member and RoundService.IsNight() and not Roster.isWolfSide(member) then
			Net.fire(player, "HouseAssigned", HouseService.Assigned[member.Id] or 0)
		end
	end)
end

return HouseService
