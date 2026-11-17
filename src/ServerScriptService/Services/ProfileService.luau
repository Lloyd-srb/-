--!strict
--[[
	ProfileService — the Match place's view of a player's saved profile
	(roles owned, level, skins) and where match rewards go.

	Storage, session locking and saving are done by ServerStorage.ServerShared
	.Profiles (shared with the Lobby place); Robux receipts by .Purchases (a
	purchase still pending from the lobby may arrive here).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ServerShared = ServerStorage:WaitForChild("ServerShared")
local ProfileLogic = require(ServerShared.Logic.ProfileLogic)
local Profiles = require(ServerShared.Profiles)
local Purchases = require(ServerShared.Purchases)

local RoleAssignment = require(script.Parent.Parent.Logic.RoleAssignment)

export type Grant = ProfileLogic.MatchGrant

local DEBUG_LEVEL = 99

local ProfileService = {}

-- (player, data): the profile finished loading (role options may change).
ProfileService.Loaded = Profiles.Loaded

-- The loaded profile, or nil while it is still loading.
function ProfileService.Get(player: Player): ProfileLogic.Data?
	return Profiles.Get(player)
end

function ProfileService.Level(player: Player): number
	if Config.Debug.Enabled and Config.Debug.UnlockAllRoles then
		return DEBUG_LEVEL
	end
	local data = Profiles.Get(player)
	return if data then ProfileLogic.level(data) else Config.PlayerLevel.StartLevel
end

-- Roles this player may put on the role screen: owned and level gate passed.
-- Until the profile has loaded: the free roles.
function ProfileService.UsableRoles(player: Player): { [Config.RoleId]: boolean }
	local owned: { [Config.RoleId]: boolean } = {}
	local data = Profiles.Get(player)
	for _, roleId in Config.RoleOrder do
		local free = Config.Roles[roleId].Free
		if free or (data and ProfileLogic.ownsRole(data, roleId)) or (Config.Debug.Enabled and Config.Debug.UnlockAllRoles) then
			owned[roleId] = true
		end
	end
	return RoleAssignment.usableRoles(owned, ProfileService.Level(player))
end

-- The skin this player wears in a slot ("Gun" / "Knife" / "Wolf"), if any.
function ProfileService.Skin(player: Player?, slot: string): string?
	local data = if player then Profiles.Get(player) else nil
	return if data then ProfileLogic.equippedSkin(data, slot) else nil
end

--[[
	Adds a match reward to the profile (saved with it). Returns the diamonds
	earned from new mastery levels (GDD §13: 20 points = 1 mastery = 20
	diamonds). Season Pass rewards reached are given at the same time.
]]
function ProfileService.Grant(player: Player, grant: Grant): number
	local diamonds = 0
	local updated = Profiles.Update(player, function(data: ProfileLogic.Data)
		diamonds = ProfileLogic.grantMatch(data, grant)
	end)
	if not updated then
		warn(`[ProfileService] {player.Name}'s profile is not loaded: this reward is lost`)
	end
	return diamonds
end

function ProfileService.Init()
	Profiles.Init()
	Purchases.Init()
end

function ProfileService.Start()
	Profiles.Start()
	Purchases.Start()
end

return ProfileService
