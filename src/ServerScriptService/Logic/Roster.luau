--!strict
--[[
	Roster — pure record of who is in the match: role, faction, alive / dead,
	kill counts. Feeds WinConditions and (later) the scoreboard and rewards.
	Ids are UserIds; debug bots use negative ids.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WinConditions = require(script.Parent.WinConditions)

-- "Wolf" | "Pup" | "Killer" | "Sheriff" | "Exile" | "Left"
export type DeathCause = string

export type Member = {
	Id: number,
	Name: string,
	IsBot: boolean,
	Role: Config.RoleId,
	Faction: Config.Faction,
	Alive: boolean,
	IsPup: boolean, -- converted villager (wolf side)
	Left: boolean,
	Kills: number,
	NightsSurvived: number,
	TasksCompleted: number,
	DeathCause: DeathCause?,
}

export type Roster = {
	Members: { [number]: Member },
	Order: { number }, -- join order, for stable iteration
	PupsCreated: number,
	WolfKills: number, -- wolf + pup
	KillerKills: number,
	-- How many nights had started when the main wolf was lost (nil = still here).
	MainWolfLostAtNight: number?,
}

local Roster = {}

function Roster.new(): Roster
	return {
		Members = {},
		Order = {},
		PupsCreated = 0,
		WolfKills = 0,
		KillerKills = 0,
		MainWolfLostAtNight = nil,
	}
end

function Roster.add(roster: Roster, id: number, name: string, isBot: boolean): Member
	local member: Member = {
		Id = id,
		Name = name,
		IsBot = isBot,
		Role = "Villager",
		Faction = "Village",
		Alive = true,
		IsPup = false,
		Left = false,
		Kills = 0,
		NightsSurvived = 0,
		TasksCompleted = 0,
		DeathCause = nil,
	}
	roster.Members[id] = member
	table.insert(roster.Order, id)
	return member
end

function Roster.setRoles(roster: Roster, roles: { [number]: Config.RoleId })
	for id, roleId in roles do
		local member = roster.Members[id]
		if member then
			member.Role = roleId
			member.Faction = Config.Roles[roleId].Faction
		end
	end
end

function Roster.list(roster: Roster): { Member }
	local members = {}
	for _, id in roster.Order do
		table.insert(members, roster.Members[id])
	end
	return members
end

function Roster.alive(roster: Roster): { Member }
	local members = {}
	for _, id in roster.Order do
		local member = roster.Members[id]
		if member.Alive then
			table.insert(members, member)
		end
	end
	return members
end

function Roster.aliveMap(roster: Roster): { [number]: boolean }
	local map: { [number]: boolean } = {}
	for _, member in Roster.alive(roster) do
		map[member.Id] = true
	end
	return map
end

function Roster.isWolfSide(member: Member): boolean
	return member.Faction == "Wolf"
end

-- The living main wolf (not the pup), if any.
function Roster.mainWolf(roster: Roster): Member?
	for _, member in Roster.alive(roster) do
		if member.Faction == "Wolf" and not member.IsPup then
			return member
		end
	end
	return nil
end

function Roster.pup(roster: Roster): Member?
	for _, member in Roster.alive(roster) do
		if member.IsPup then
			return member
		end
	end
	return nil
end

-- The living member holding `roleId` (special roles are unique).
function Roster.findRole(roster: Roster, roleId: Config.RoleId): Member?
	for _, member in Roster.alive(roster) do
		if member.Role == roleId and not member.IsPup then
			return member
		end
	end
	return nil
end

function Roster.snapshot(roster: Roster): WinConditions.Snapshot
	local wolves, others, killerAlive = 0, 0, false
	for _, member in Roster.alive(roster) do
		if member.Faction == "Wolf" then
			wolves += 1
		elseif member.Faction == "Killer" then
			killerAlive = true
		else
			others += 1
		end
	end
	return {
		WolfSideAlive = wolves,
		KillerAlive = killerAlive,
		OthersAlive = others,
		WolfKills = roster.WolfKills,
		KillerKills = roster.KillerKills,
	}
end

local function credit(roster: Roster, killerId: number?, cause: DeathCause)
	if cause == "Wolf" or cause == "Pup" then
		roster.WolfKills += 1
	elseif cause == "Killer" then
		roster.KillerKills += 1
	end
	if killerId then
		local killer = roster.Members[killerId]
		if killer then
			killer.Kills += 1
		end
	end
end

--[[
	Marks a member dead. `nightsStarted` = nights begun so far (for the pup's
	promotion countdown when the main wolf is lost). Returns false if the
	member was already dead / unknown.
]]
function Roster.recordDeath(
	roster: Roster,
	id: number,
	cause: DeathCause,
	nightsStarted: number,
	killerId: number?
): boolean
	local member = roster.Members[id]
	if not member or not member.Alive then
		return false
	end
	local wasMainWolf = member.Faction == "Wolf" and not member.IsPup
	member.Alive = false
	member.DeathCause = cause
	if cause == "Left" then
		member.Left = true
	end
	credit(roster, killerId, cause)
	if wasMainWolf then
		roster.MainWolfLostAtNight = nightsStarted
	end
	return true
end

-- The wolf's first night victim joins the wolf side instead of dying (GDD §8.2).
-- Counts as a wolf kill.
function Roster.convertToPup(roster: Roster, id: number, wolfId: number?): boolean
	local member = roster.Members[id]
	if not member or not member.Alive or member.Faction == "Wolf" then
		return false
	end
	member.Faction = "Wolf"
	member.IsPup = true
	roster.PupsCreated += 1
	credit(roster, wolfId, "Wolf")
	return true
end

-- The pup grows into the main wolf.
function Roster.promotePup(roster: Roster): Member?
	local pup = Roster.pup(roster)
	if pup then
		pup.IsPup = false
		pup.Role = "Wolf"
		roster.MainWolfLostAtNight = nil
	end
	return pup
end

-- Call when a night ends: everyone still alive survived it.
function Roster.creditNightSurvived(roster: Roster)
	for _, member in Roster.alive(roster) do
		member.NightsSurvived += 1
	end
end

return Roster
