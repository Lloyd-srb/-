--!strict
--[[
	ArsonService — the Fire Maniac (owner, 18 Nov 2026).
	  - Hold E right next to any wall of a house to pour oil on it: once by day
	    and once by night. The prompts sit along every outside wall and only
	    show up close to the wall (Config.Abilities.FireManiac.WallReach).
	  - Only the Fire Maniac's client shows them (Audience "Role:FireManiac").
	  - No marks on oiled houses: the Fire Maniac must remember. An oiled
	    house's prompts just stop appearing.
	  - Every house oiled (all different) -> the Fire Maniac wins the next
	    morning, if still alive ([ASSUMED]).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)
local Zones = require(ReplicatedStorage.Shared.Zones)

local Logic = script.Parent.Parent.Logic
local AbilityUses = require(Logic.AbilityUses)
local Roster = require(Logic.Roster)
local WinConditions = require(Logic.WinConditions)

local AudioService = require(script.Parent.AudioService)
local CombatService = require(script.Parent.CombatService)
local HidingService = require(script.Parent.HidingService)
local HouseService = require(script.Parent.HouseService)
local MatchService = require(script.Parent.MatchService)
local Net = require(script.Parent.Net)
local Prompts = require(script.Parent.Prompts)
local RoundService = require(script.Parent.RoundService)

local REACH_SLACK = 4 -- extra studs allowed over a prompt's activation distance (lag)
local PROMPT_HEIGHT = 3 -- studs above the floor

local ArsonService = {}

local oiled: { [number]: boolean } = {} -- house id -> oil poured
local prompts: { [number]: { ProximityPrompt } } = {}
local uses = AbilityUses.new()

-- The current limit scope: ("Day:3", "Day") / ("Night:2", "Night") / nil.
local function scope(): (string?, string?)
	local state = RoundService.State
	if state.Phase == "Night" then
		return "Night:" .. state.Night, "Night"
	elseif state.Phase == "Day" or state.Phase == "MeetingCountdown" then
		return "Day:" .. state.Day, "Day"
	end
	return nil, nil
end

function ArsonService.OiledCount(): number
	local count = 0
	for _ in oiled do
		count += 1
	end
	return count
end

function ArsonService.IsOiled(houseId: number): boolean
	return oiled[houseId] == true
end

local function fireManiac(): Roster.Member?
	for _, member in Roster.list(MatchService.Roster) do
		if member.Role == "FireManiac" then
			return member
		end
	end
	return nil
end

local function refresh()
	local open = scope() ~= nil and not MatchService.Winner
	for houseId, list in prompts do
		local active = open and not oiled[houseId]
		for _, prompt in list do
			prompt:SetAttribute("Active", active)
			prompt.Enabled = active
		end
	end
end

local function worldPosition(prompt: ProximityPrompt): Vector3?
	local anchor = prompt.Parent
	if anchor and anchor:IsA("Attachment") then
		return Zones.worldCFrame(anchor).Position
	elseif anchor and anchor:IsA("BasePart") then
		return anchor.CFrame.Position
	end
	return nil
end

local function onPrompt(player: Player, houseId: number, prompt: ProximityPrompt)
	local member = MatchService.MemberOf(player)
	if not member or not member.Alive or member.Role ~= "FireManiac" or MatchService.Winner or not MatchService.Started then
		return
	end
	if HidingService.IsHidden(member.Id) or CombatService.IsStunned(member.Id) or oiled[houseId] then
		return
	end
	local scopeKey = scope()
	local cfg = Config.Abilities.FireManiac
	if not scopeKey then
		return
	end
	if AbilityUses.left(uses, member.Id, "Oil", scopeKey, cfg.UsesPerPhase) <= 0 then
		Net.fire(player, "Effect", { Kind = "OilUsed" })
		return
	end
	local root = MatchService.RootOf(member.Id)
	local at = worldPosition(prompt)
	if not root or not at or (root.CFrame.Position - at).Magnitude > prompt.MaxActivationDistance + REACH_SLACK then
		return
	end
	AbilityUses.tryUse(uses, member.Id, "Oil", scopeKey, cfg.UsesPerPhase)
	oiled[houseId] = true
	refresh()
	AudioService.To(player, "OilPour")
	Net.fire(player, "Effect", { Kind = "OilPoured" }) -- no house number: the Fire Maniac must remember
end

-- Prompts every few studs along the four outside walls of a house.
local function buildPrompts(houseId: number)
	local zone = HouseService.ZoneOf(houseId)
	if not zone then
		return
	end
	local cfg = Config.Abilities.FireManiac
	local anchor = Instance.new("Part")
	anchor.Name = "OilAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = zone.CFrame
	anchor.Parent = zone.Parent

	local half = zone.Size / 2
	local wall = 1 -- the walls are 1 stud thick, just outside the zone
	local outX, outZ = half.X + wall + 0.5, half.Z + wall + 0.5
	local y = -half.Y + PROMPT_HEIGHT
	local points: { Vector3 } = {}
	local function along(fromV: Vector3, toV: Vector3)
		local length = (toV - fromV).Magnitude
		local steps = math.max(1, math.floor(length / cfg.PromptSpacing))
		for index = 0, steps do
			table.insert(points, fromV:Lerp(toV, index / steps))
		end
	end
	along(Vector3.new(-outX, y, -outZ), Vector3.new(outX, y, -outZ)) -- front
	along(Vector3.new(-outX, y, outZ), Vector3.new(outX, y, outZ)) -- back
	along(Vector3.new(-outX, y, -outZ + cfg.PromptSpacing), Vector3.new(-outX, y, outZ - cfg.PromptSpacing)) -- left
	along(Vector3.new(outX, y, -outZ + cfg.PromptSpacing), Vector3.new(outX, y, outZ - cfg.PromptSpacing)) -- right

	local list: { ProximityPrompt } = {}
	for index, point in points do
		local attachment = Instance.new("Attachment")
		attachment.Name = "Oil" .. index
		attachment.CFrame = CFrame.new(point)
		attachment.Parent = anchor
		local prompt = Prompts.create(attachment, "OilPrompt", "Prompt.Oil", cfg.Hold)
		prompt.MaxActivationDistance = cfg.WallReach
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("Audience", "Role:FireManiac")
		prompt:SetAttribute("HouseId", houseId)
		prompt.Triggered:Connect(function(player: Player)
			onPrompt(player, houseId, prompt)
		end)
		table.insert(list, prompt)
	end
	prompts[houseId] = list
end

function ArsonService.Init() end

function ArsonService.Start()
	for _, houseId in HouseService.Ids() do
		buildPrompts(houseId)
	end
	refresh()

	RoundService.PhaseStarted:Connect(function(state: PhaseMachine.PhaseState)
		if state.Phase == "Day" and not MatchService.Winner then
			local maniac = fireManiac()
			if maniac and WinConditions.fireManiacWins(ArsonService.OiledCount(), HouseService.Count(), maniac.Alive) then
				MatchService.DeclareWinner("FireManiac")
			end
		end
		refresh()
	end)
	MatchService.MatchStarted:Connect(function()
		table.clear(oiled)
		refresh()
	end)
end

return ArsonService
