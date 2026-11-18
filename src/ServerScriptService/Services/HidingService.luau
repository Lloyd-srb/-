--!strict
--[[
	HidingService — hiding under beds / in wardrobes and the wolf's search
	(GDD §6.4).

	Information hiding: a hidden player's body is parked far away from the map
	and only that player is told which spot they are in (their camera sits at
	the spot). Nobody else can tell where anyone hides, not even by reading
	character positions. The wolf has to search spot by spot.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)
local Zones = require(ReplicatedStorage.Shared.Zones)

local Logic = script.Parent.Parent.Logic
local HidingState = require(Logic.HidingState)
local Roster = require(Logic.Roster)

local HouseService = require(script.Parent.HouseService)
local MatchService = require(script.Parent.MatchService)
local MovementGuard = require(script.Parent.MovementGuard)
local Net = require(script.Parent.Net)
local Prompts = require(script.Parent.Prompts)
local RoundService = require(script.Parent.RoundService)

type Spot = {
	Key: string,
	HouseId: number,
	Model: Model,
	Anchor: BasePart,
	HidePrompt: ProximityPrompt,
	SearchPrompt: ProximityPrompt,
}

local HidingService = {}

local state = HidingState.new()
local spots: { [string]: Spot } = {}
local parked: { [number]: number } = {} -- member id -> holding slot
local nextSlot = 0

function HidingService.IsHidden(id: number): boolean
	return HidingState.isHidden(state, id)
end

local function setPrompts(active: boolean)
	for _, spot in spots do
		for _, prompt in { spot.HidePrompt, spot.SearchPrompt } do
			prompt:SetAttribute("Active", active)
			prompt.Enabled = active
		end
	end
end

local function spotCFrame(spot: Spot, attachmentName: string): CFrame
	local attachment = spot.Anchor:FindFirstChild(attachmentName)
	if attachment and attachment:IsA("Attachment") then
		return Zones.worldCFrame(attachment)
	end
	return spot.Anchor.CFrame
end

-- Close to the spot AND inside its house: prompts do not need line of sight,
-- so without the house check a wolf could search a bed through the back wall.
local function near(id: number, spot: Spot): boolean
	local root = MatchService.RootOf(id)
	if not root then
		return false
	end
	local position = root.CFrame.Position
	return (position - spot.Anchor.CFrame.Position).Magnitude <= Config.Human.InteractDistance + 4
		and HouseService.HouseAt(position) == spot.HouseId
		and not HouseService.IsTrespassing(id)
end

-- Streaming focus follows the hiding spot while hidden (nil = the body again).
-- pcall: offline tooling cannot store a nil reference; Roblox can.
local function setFocus(player: Player, target: Instance?)
	pcall(function()
		player.ReplicationFocus = target
	end)
end

-- Puts a hidden member back into the world next to their spot.
local function release(id: number, spot: Spot?)
	local root = MatchService.RootOf(id)
	if root then
		root.Anchored = false
	end
	parked[id] = nil
	if spot then
		MovementGuard.Warp(id, spotCFrame(spot, "ExitSpot"))
	end
	local player = MatchService.PlayerOf(id)
	if player then
		setFocus(player, nil)
		Net.fire(player, "HideChanged", nil)
	end
end

local function onHide(player: Player, spot: Spot)
	local member = MatchService.MemberOf(player)
	if not member or not member.Alive or Roster.isWolfSide(member) or not RoundService.IsNight() then
		return
	end
	if not near(member.Id, spot) or not HidingState.hide(state, member.Id, spot.Key) then
		return
	end
	local character = MatchService.CharacterOf(member.Id)
	local root = MatchService.RootOf(member.Id)
	if character and root then
		nextSlot += 1
		parked[member.Id] = nextSlot
		root.Anchored = true
		MovementGuard.Warp(member.Id, CFrame.new(nextSlot * Config.Hiding.HoldingSpacing, Config.Hiding.HoldingHeight, 0))
	end
	-- Only the hider learns the spot (their camera moves there). The body is
	-- parked far away, so keep streaming focused on the spot, not the body.
	setFocus(player, spot.Anchor)
	Net.fire(player, "HideChanged", spot.Anchor)
end

local function onSearch(player: Player, spot: Spot)
	local member = MatchService.MemberOf(player)
	if not member or not member.Alive or not Roster.isWolfSide(member) or not RoundService.IsNight() then
		return
	end
	if not near(member.Id, spot) then
		return
	end
	-- Thrown out, not stunned, and cannot hide again tonight.
	local foundId = HidingState.search(state, spot.Key)
	if foundId then
		release(foundId, spot)
	end
end

local function onExit(player: Player)
	local key = HidingState.leave(state, player.UserId)
	if key then
		release(player.UserId, spots[key])
	end
end

local function releaseEveryone()
	for _, id in HidingState.hiddenIds(state) do
		local key = HidingState.leave(state, id)
		release(id, if key then spots[key] else nil)
	end
	HidingState.reset(state)
end

local function register(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local houseId = model:GetAttribute("HouseId")
	local kind = model:GetAttribute("Kind")
	local anchor = model.PrimaryPart
	if type(houseId) ~= "number" or type(kind) ~= "string" or not anchor then
		warn(`[HidingService] {model:GetFullName()} is not a valid hiding spot; rebuild the map`)
		return
	end
	local promptParent = anchor:FindFirstChild("PromptAnchor") or anchor
	local spot: Spot = {
		Key = HidingState.spotKey(houseId, kind),
		HouseId = houseId,
		Model = model,
		Anchor = anchor,
		HidePrompt = Prompts.create(promptParent, "HidePrompt", "Prompt.Hide", Config.Human.HideHold),
		SearchPrompt = Prompts.create(promptParent, "SearchPrompt", "Prompt.Search", Config.Wolf.SearchHold),
	}
	-- Clients show "Hide" to humans and "Search" to the wolf side only.
	spot.HidePrompt:SetAttribute("Audience", "Human")
	spot.SearchPrompt:SetAttribute("Audience", "Wolf")
	spot.HidePrompt.Triggered:Connect(function(player: Player)
		onHide(player, spot)
	end)
	spot.SearchPrompt.Triggered:Connect(function(player: Player)
		onSearch(player, spot)
	end)
	spots[spot.Key] = spot
end

function HidingService.Init()
	for _, model in CollectionService:GetTagged("HidingSpot") do
		register(model)
	end
end

function HidingService.Start()
	Net.on("HideExit", onExit, 6, 5)
	HouseService.IsHidden = HidingService.IsHidden -- a hidden body is parked far away, not "out"

	RoundService.PhaseStarted:Connect(function(phase: PhaseMachine.PhaseState)
		if phase.Phase == "Night" then
			HidingState.reset(state)
			setPrompts(true)
		end
	end)
	-- Before the morning warp: everybody comes out.
	RoundService.PhaseEnded:Connect(function(phase: PhaseMachine.PhaseState)
		if phase.Phase == "Night" then
			setPrompts(false)
			releaseEveryone()
		end
	end)
	MatchService.MemberDied:Connect(function(member: Roster.Member)
		HidingState.leave(state, member.Id)
		parked[member.Id] = nil
	end)
	-- A fresh body is never inside a hiding spot.
	MatchService.BodyReplaced:Connect(function(member: Roster.Member)
		local key = HidingState.leave(state, member.Id)
		if key then
			release(member.Id, spots[key])
		end
	end)
	MatchService.MemberConverted:Connect(function(member: Roster.Member)
		local key = HidingState.leave(state, member.Id)
		if key then
			release(member.Id, spots[key])
		end
	end)
end

return HidingService
