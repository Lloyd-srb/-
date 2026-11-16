--!strict
--[[
	CombatService — health, damage and what a death turns into.

	Health lives on the server (mirrored to the Humanoid for the health bar).
	Every attack in the game goes through Damage(), so shields (blessing,
	Cross), the pup conversion and corpses are handled in one place.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Logic = script.Parent.Parent.Logic
local Roster = require(Logic.Roster)
local WolfPack = require(Logic.WolfPack)

local MatchService = require(script.Parent.MatchService)
local Ragdoll = require(script.Parent.Ragdoll)

-- "None" | "Blocked" | "Hurt" | "Killed" | "Converted"
export type Outcome = string

-- A shield returns true when it absorbed the hit (and consumed itself).
export type Shield = (victimId: number, cause: Roster.DeathCause) -> boolean

local CombatService = {}

local health: { [number]: number } = {}
local shields: { Shield } = {}

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
		Ragdoll.apply(body)
	end
	MatchService.CheckWin()
	return "Killed"
end

function CombatService.Init() end

function CombatService.Start()
	MatchService.MatchStarted:Connect(function()
		for _, member in Roster.list(MatchService.Roster) do
			CombatService.Heal(member.Id)
		end
	end)
end

return CombatService
