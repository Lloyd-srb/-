--[[
	The two places of the experience and how to rebuild each from the repo.
	  Match  src/ (everything) + build/*
	  Lobby  lobby/src/ + the shared code from src/ReplicatedStorage and
	         src/ServerStorage + build/lobby/* (and the shared lighting builder)
]]

local Places = {}

Places.Match = {
	Name = "Match",
	Roots = { { Dir = "src" } },
	Builders = {
		"build/BuildVillage.luau",
		"build/BuildLighting.luau",
		"build/BuildUI.luau",
		"build/BuildSettings.luau",
		"build/BuildWolfRig.luau",
	},
	BuilderDirs = { "build" }, -- shipped inside the place as ServerStorage.Builders
	Out = "out/WolfVillage.rbxl",
	Sourcemap = "sourcemap.json",
	Analyze = { "src", "build" },
}

Places.Lobby = {
	Name = "Lobby",
	Roots = {
		{ Dir = "lobby/src" },
		{ Dir = "src/ReplicatedStorage", Prefix = { "ReplicatedStorage" } },
		{ Dir = "src/ServerStorage", Prefix = { "ServerStorage" } },
	},
	Builders = {
		"build/lobby/BuildLobby.luau",
		"build/BuildLighting.luau",
		"build/lobby/BuildLobbyUI.luau",
	},
	BuilderDirs = { "build/lobby" },
	Out = "out/WolfVillageLobby.rbxl",
	Sourcemap = "sourcemap.lobby.json",
	Analyze = { "lobby", "build/lobby" },
}

Places.All = { Places.Match, Places.Lobby }

return Places
