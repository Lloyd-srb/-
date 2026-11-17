--!strict
--[[
	GhostService — the dead become ghosts (GDD §12).

	A player who dies or is exiled gets a new, invisible body: the ghost. It
	can walk around, but the living never see it (its parts are fully
	transparent on the server; only ghosts' own clients make ghosts visible,
	see GhostController), it cannot touch, block or be hit by anything, and
	it cannot use prompts or abilities (every service checks "alive").
	A night death leaves the corpse where it fell; the ghost appears next to it.
	Players can leave at any time (Roblox menu) without penalty.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Zones = require(ReplicatedStorage.Shared.Zones)

local Roster = require(script.Parent.Parent.Logic.Roster)

local MatchService = require(script.Parent.MatchService)

local GHOST_RISE = 3 -- the ghost stands this far above where the body lay
local RESPAWN_DELAY = 1

local GhostService = {}

local function plazaSpot(): Vector3
	local map = workspace:FindFirstChild("Map")
	local markers = map and map:FindFirstChild("Markers")
	local spot = markers and markers:FindFirstChild("PupSpawn")
	if spot and spot:IsA("Attachment") then
		return Zones.worldCFrame(spot).Position
	end
	return Vector3.new(0, 3, 0)
end

-- Lets the corpse stay in the world when the player gets a new body.
local function detach(player: Player)
	-- pcall: offline tooling cannot store a nil reference; Roblox can.
	pcall(function()
		player.Character = nil
	end)
end

local makeGhost: (player: Player, member: Roster.Member, at: Vector3) -> ()

-- Makes one piece of a ghost invisible and untouchable on the server.
local function conceal(instance: Instance)
	if instance:IsA("BasePart") then
		instance.Transparency = 1
		instance.CanQuery = false -- shots, swings and line-of-sight ignore ghosts
		instance.CanTouch = false
		instance.CollisionGroup = MatchService.GhostGroup
	elseif instance:IsA("Decal") then
		instance.Transparency = 1
	end
end

local function setUpGhost(player: Player, member: Roster.Member, ghost: Model)
	ghost:AddTag("Ghost")
	ghost:SetAttribute("MemberId", member.Id)
	for _, instance in ghost:GetDescendants() do
		conceal(instance)
	end
	-- Hats, hair and clothing can arrive after the body itself: they must not
	-- float around visible to the living (or stop a shot).
	ghost.DescendantAdded:Connect(conceal)
	local humanoid = ghost:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.Died:Connect(function()
			-- Fell out of the world or similar: a ghost simply comes back.
			task.delay(RESPAWN_DELAY, function()
				if not member.Alive and player.Parent and player.Character == ghost then
					makeGhost(player, member, plazaSpot())
				end
			end)
		end)
	end
end

function makeGhost(player: Player, member: Roster.Member, at: Vector3)
	if member.Alive or not player.Parent then
		return
	end
	local corpse = MatchService.BodyOf(member.Id)
	if corpse and corpse == player.Character then
		detach(player)
	end
	player:LoadCharacterAsync()
	local ghost = player.Character
	if not ghost or member.Alive then
		return
	end
	setUpGhost(player, member, ghost)
	ghost:PivotTo(CFrame.new(at + Vector3.new(0, GHOST_RISE, 0)))
end

function GhostService.Init() end

function GhostService.Start()
	MatchService.MemberDied:Connect(function(member: Roster.Member, cause: Roster.DeathCause)
		local player = MatchService.PlayerOf(member.Id)
		if not player or member.IsBot or cause == "Left" then
			return
		end
		-- Where the body falls, or the plaza for the exiled (they leave no body).
		local at = plazaSpot()
		if cause ~= "Exile" then
			local body = MatchService.BodyOf(member.Id)
			local root = body and body:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				at = root.CFrame.Position
			end
		end
		-- Deferred: the killing code first turns the old body into a corpse.
		task.defer(makeGhost, player, member, at)
	end)
end

function GhostService.IsGhost(model: Instance): boolean
	return model:HasTag("Ghost")
end

return GhostService
