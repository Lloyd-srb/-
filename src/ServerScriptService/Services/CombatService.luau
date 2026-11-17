--!strict
--[[
	CombatService — health, damage and what a death turns into.

	Health lives on the server (mirrored to the Humanoid for the health bar).
	Every attack in the game goes through Damage(), so shields (blessing,
	Cross), the pup conversion and corpses are handled in one place.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

local Logic = script.Parent.Parent.Logic
local Roster = require(Logic.Roster)
local WolfPack = require(Logic.WolfPack)

local MatchService = require(script.Parent.MatchService)
local MoveService = require(script.Parent.MoveService)
local Net = require(script.Parent.Net)
local Ragdoll = require(script.Parent.Ragdoll)

-- "None" | "Blocked" | "Hurt" | "Killed" | "Converted"
export type Outcome = string

-- A shield returns true when it absorbed the hit (and consumed itself).
export type Shield = (victimId: number, cause: Roster.DeathCause) -> boolean

local STUN_KEY = "Stun"

local CombatService = {}

CombatService.CorpseCreated = Signal.new() -- (member, body)

local health: { [number]: number } = {}
local shields: { Shield } = {}
local stunnedUntil: { [number]: number } = {}
local stunImmunities: { (id: number) -> boolean } = {}

local function mirror(id: number)
	local humanoid = MatchService.HumanoidOf(id)
	if humanoid then
		-- Never let the Humanoid itself die: the server decides what death means.
		humanoid.Health = math.max(1, health[id] or Config.Human.MaxHealth)
	end
end

function CombatService.Health(id: number): number
	return health[id] or Config.Human.MaxHealth
end

function CombatService.Heal(id: number)
	health[id] = Config.Human.MaxHealth
	mirror(id)
end

-- Blessing / Cross register here (milestones 4 and 5).
function CombatService.AddShield(shield: Shield)
	table.insert(shields, shield)
end

function CombatService.Damage(victimId: number, amount: number, cause: Roster.DeathCause, attackerId: number?): Outcome
	local roster = MatchService.Roster
	local victim = roster.Members[victimId]
	if not victim or not victim.Alive or MatchService.Winner then
		return "None"
	end
	for _, shield in shields do
		if shield(victimId, cause) then
			-- Only the two people involved learn that something blocked the hit.
			local involved: { number } = { victimId }
			if attackerId then
				table.insert(involved, attackerId)
			end
			for _, id in involved do
				local player = MatchService.PlayerOf(id)
				if player then
					Net.fire(player, "Effect", { Kind = "Blocked" })
				end
			end
			return "Blocked"
		end
	end

	local remaining = CombatService.Health(victimId) - amount
	health[victimId] = remaining
	if remaining > 0 then
		mirror(victimId)
		return "Hurt"
	end

	-- The main wolf's first night victim becomes the pup instead of dying.
	if WolfPack.shouldConvert(cause == "Wolf", MatchService.IsNight(), roster.PupsCreated) then
		CombatService.Heal(victimId)
		if MatchService.ConvertToPup(victimId, attackerId) then
			return "Converted"
		end
	end

	local body = MatchService.CharacterOf(victimId)
	if not MatchService.Kill(victimId, cause, attackerId) then
		return "None"
	end
	if body then
		MatchService.MarkCorpse(victimId, body)
		Ragdoll.apply(body)
		CombatService.CorpseCreated:Fire(roster.Members[victimId], body)
	end
	MatchService.CheckWin()
	return "Killed"
end

--------------------------------------------------------------------------------
-- Stun: cannot move or act for a few seconds (stun gun, bodyguard, shovel, axe)
--------------------------------------------------------------------------------

function CombatService.IsStunned(id: number): boolean
	return os.clock() < (stunnedUntil[id] or 0)
end

-- e.g. a mauling wolf cannot be stunned (GDD §8.1).
function CombatService.AddStunImmunity(isImmune: (id: number) -> boolean)
	table.insert(stunImmunities, isImmune)
end

local function clearStun(id: number)
	stunnedUntil[id] = nil
	MoveService.ClearModifier(id, STUN_KEY)
	local body = MatchService.BodyOf(id)
	if body then
		body:SetAttribute("Stunned", nil)
	end
end

-- Returns false when the target is dead or immune.
function CombatService.Stun(id: number, seconds: number): boolean
	local member = MatchService.Roster.Members[id]
	if not member or not member.Alive or MatchService.Winner then
		return false
	end
	for _, isImmune in stunImmunities do
		if isImmune(id) then
			return false
		end
	end
	local untilTime = math.max(stunnedUntil[id] or 0, os.clock() + seconds)
	stunnedUntil[id] = untilTime
	MoveService.SetModifier(id, STUN_KEY, { Override = 0, NoJump = true })
	local body = MatchService.CharacterOf(id)
	if body then
		body:SetAttribute("Stunned", true) -- lets every client show the effect
	end
	task.delay(seconds, function()
		if stunnedUntil[id] == untilTime then
			clearStun(id)
		end
	end)
	return true
end

function CombatService.Init() end

function CombatService.Start()
	MatchService.MatchStarted:Connect(function()
		for _, member in Roster.list(MatchService.Roster) do
			CombatService.Heal(member.Id)
		end
	end)
	MatchService.MemberDied:Connect(function(member: Roster.Member)
		if stunnedUntil[member.Id] then
			clearStun(member.Id)
		end
	end)
	MatchService.MemberRevived:Connect(function(member: Roster.Member)
		CombatService.Heal(member.Id)
		MoveService.Refresh(member.Id)
	end)
	-- A new body keeps the old health (resetting must not heal you).
	MatchService.BodyReplaced:Connect(function(member: Roster.Member)
		mirror(member.Id)
		MoveService.Refresh(member.Id)
	end)
end

return CombatService
