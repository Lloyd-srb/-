--!strict
--[[
	RoleAssignment — pure role-assignment rules (GDD §2, §4).

	1. The wolf is random; nobody can choose it.
	2. Everyone else gets one of the 3 roles they picked. No duplicates except Villager.
	3. Special roles are capped by the match's special slots (by player count,
	   Config.Match.SpecialSlots). Killer and Fool are their own factions: they
	   do not use a special slot, they replace a villager; both together only
	   with 11-12 players (owner, 17 Nov 2026).
	4. When all of a player's picks are gone:
	     a) a random other village role they own that is still free
	        ([owner] 17 Nov 2026: never the Killer or the Fool, whose goal is
	        different, unless the player picked them), else
	     b) Villager.
	5. Lovers ([owner] 18 Nov 2026): two players can be Lovers (Copies = 2).
	   If only one got it, one random player who was going to be a Villager
	   becomes the other Lover.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rng = require(ReplicatedStorage.Shared.Rng)

type RoleId = Config.RoleId
type ModeDef = Config.ModeDef

export type Candidate = {
	Id: number, -- UserId
	Picks: { RoleId }, -- validated picks (see validatePicks)
	Usable: { [RoleId]: boolean }, -- owned AND level requirement met
}

local RoleAssignment = {}

-- How many of each kind of role a match of `players` has.
function RoleAssignment.composition(players: number): ModeDef
	local cfg = Config.Match
	local special = cfg.SpecialSlots[players] or math.floor(players / 2)
	return {
		Players = players,
		Wolves = cfg.Wolves,
		SpecialSlots = special,
		MaxSolo = if players >= cfg.BothSoloFrom then 2 else 1,
	}
end

-- Roles a player may pick: owned and level gate passed (§4.6).
function RoleAssignment.usableRoles(owned: { [RoleId]: boolean }, level: number): { [RoleId]: boolean }
	local usable: { [RoleId]: boolean } = {}
	for _, roleId in Config.RoleOrder do
		local def = Config.Roles[roleId]
		if (def.Free or owned[roleId]) and level >= def.RequiredLevel then
			usable[roleId] = true
		end
	end
	return usable
end

-- Server-side validation of a client's picks.
function RoleAssignment.validatePicks(picks: { RoleId }, usable: { [RoleId]: boolean }): (boolean, string?)
	if #picks ~= Config.RoleSelect.PickCount then
		return false, "WrongPickCount"
	end
	local seen: { [RoleId]: boolean } = {}
	for _, roleId in picks do
		if roleId == "Wolf" or Config.Roles[roleId] == nil then
			return false, "UnknownRole"
		elseif not usable[roleId] then
			return false, "RoleNotUsable"
		elseif seen[roleId] then
			return false, "DuplicatePick"
		end
		seen[roleId] = true
	end
	return true, nil
end

-- Picks used when a player did not confirm in time: random usable roles.
function RoleAssignment.defaultPicks(usable: { [RoleId]: boolean }, rng: Rng.Rng): { RoleId }
	local pool: { RoleId } = {}
	for _, roleId in Config.RoleOrder do
		if usable[roleId] then
			table.insert(pool, roleId)
		end
	end
	pool = Rng.shuffle(pool, rng)
	local picks: { RoleId } = {}
	for i = 1, math.min(Config.RoleSelect.PickCount, #pool) do
		picks[i] = pool[i]
	end
	return picks
end

--[[
	Assigns a role to every candidate.
	`forced` (Studio debug only) maps UserId -> role and is applied first.
]]
function RoleAssignment.assign(
	candidates: { Candidate },
	mode: ModeDef,
	rng: Rng.Rng,
	forced: { [number]: RoleId }?
): { [number]: RoleId }
	local result: { [number]: RoleId } = {}
	local taken: { [RoleId]: number } = {} -- how many players have each role
	local wolves = 0
	local specialUsed = 0
	local soloUsed = 0

	local function isFree(roleId: RoleId): boolean
		local def = Config.Roles[roleId]
		local used = taken[roleId] or 0
		if def.Kind == "Special" then
			return used < (def.Copies or 1) and specialUsed < mode.SpecialSlots
		elseif def.Kind == "Filler" then
			return true
		elseif def.Kind == "Solo" then
			return used < (def.Copies or 1) and soloUsed < mode.MaxSolo
		end
		return false -- Wolf is never picked
	end

	local function give(id: number, roleId: RoleId)
		local def = Config.Roles[roleId]
		result[id] = roleId
		if def.Kind == "Wolf" then
			wolves += 1
		elseif def.Kind == "Special" then
			taken[roleId] = (taken[roleId] or 0) + 1
			specialUsed += 1
		elseif def.Kind == "Solo" then
			taken[roleId] = (taken[roleId] or 0) + 1
			soloUsed += 1
		end
	end

	local order = Rng.shuffle(candidates, rng)

	if forced then
		for _, candidate in order do
			local roleId = forced[candidate.Id]
			if roleId then
				give(candidate.Id, roleId)
			end
		end
	end

	-- 1) Wolves first, at random.
	for _, candidate in order do
		if wolves >= mode.Wolves then
			break
		end
		if result[candidate.Id] == nil then
			give(candidate.Id, "Wolf")
		end
	end

	-- 2) One of the three picks.
	local unplaced: { Candidate } = {}
	for _, candidate in order do
		if result[candidate.Id] ~= nil then
			continue
		end
		local options: { RoleId } = {}
		for _, roleId in candidate.Picks do
			if isFree(roleId) then
				table.insert(options, roleId)
			end
		end
		if #options > 0 then
			give(candidate.Id, Rng.pick(options, rng))
		else
			table.insert(unplaced, candidate)
		end
	end

	-- 3) Fallbacks for players whose picks were all taken: another role they
	--    own that is still free, else Villager.
	for _, candidate in unplaced do
		local owned: { RoleId } = {}
		for _, roleId in Config.RoleOrder do
			local def = Config.Roles[roleId]
			if roleId ~= "Villager" and def.Faction == "Village" and candidate.Usable[roleId] and isFree(roleId) then
				table.insert(owned, roleId)
			end
		end
		give(candidate.Id, if #owned > 0 then Rng.pick(owned, rng) else "Villager")
	end

	-- 4) A lone Lover gets a partner from the would-be Villagers (no slot used).
	if (taken["Lover"] or 0) == 1 then
		local villagers: { number } = {}
		for _, candidate in order do
			if result[candidate.Id] == "Villager" then
				table.insert(villagers, candidate.Id)
			end
		end
		if #villagers > 0 then
			result[Rng.pick(villagers, rng)] = "Lover"
			taken["Lover"] = 2
		end
	end

	return result
end

return RoleAssignment
