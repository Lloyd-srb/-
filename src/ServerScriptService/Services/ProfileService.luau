--!strict
--[[
	ProfileService — what a player owns (roles, level, currencies...).

	Milestone 4 only needs "which roles may this player pick", so this is an
	in-memory profile: new players own the three free roles at level 1.
	Milestone 9 replaces the storage with DataStore profiles (session locking,
	retries) behind this same interface.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Logic.Progression)

local RoleAssignment = require(script.Parent.Parent.Logic.RoleAssignment)

export type Profile = {
	Roles: { [Config.RoleId]: boolean }, -- bought / won roles (free roles are implicit)
	Exp: number,
}

local DEBUG_LEVEL = 99

local ProfileService = {}

local profiles: { [number]: Profile } = {}

function ProfileService.Get(player: Player): Profile
	local profile = profiles[player.UserId]
	if not profile then
		profile = { Roles = {}, Exp = 0 }
		profiles[player.UserId] = profile
	end
	return profile
end

function ProfileService.Level(player: Player): number
	if Config.Debug.Enabled and Config.Debug.UnlockAllRoles then
		return DEBUG_LEVEL
	end
	return Progression.playerLevel(ProfileService.Get(player).Exp)
end

-- Roles this player may put on the role screen: owned and level gate passed.
function ProfileService.UsableRoles(player: Player): { [Config.RoleId]: boolean }
	local owned = ProfileService.Get(player).Roles
	if Config.Debug.Enabled and Config.Debug.UnlockAllRoles then
		owned = {}
		for _, roleId in Config.RoleOrder do
			owned[roleId] = true
		end
	end
	return RoleAssignment.usableRoles(owned, ProfileService.Level(player))
end

function ProfileService.Init() end

function ProfileService.Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		profiles[player.UserId] = nil
	end)
end

return ProfileService
