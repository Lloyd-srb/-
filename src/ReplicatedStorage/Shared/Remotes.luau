--!strict
--[[
	Remotes — the single list of RemoteEvents. The server creates them once
	(Remotes.createAll); clients wait for them (Remotes.get).

	Server -> one client only (secret):  RoleAssigned, HouseAssigned, VoteMine,
	                                     FormChanged, PackChanged, Highlight,
	                                     AbilityState, HideChanged, RoleOptions,
	                                     RolePicksAck
	Server -> everyone (public):         PhaseChanged, Announcement, RosterChanged,
	                                     VoteOpened, VoteCounts, VoteClosed, GameOver
	Client -> server (intents):          RequestSync, VoteSelect, VoteConfirm,
	                                     WolfAttack, WolfAbility, HideExit, RolePicks
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local Remotes = {}

Remotes.Names = {
	-- server -> client
	"PhaseChanged",
	"Announcement",
	"RosterChanged",
	"RoleAssigned",
	"HouseAssigned",
	"VoteOpened",
	"VoteCounts",
	"VoteMine",
	"VoteClosed",
	"GameOver",
	"FormChanged", -- "Human" | "Wolf" | "Pup" (own form)
	"PackChanged", -- wolf side only: ids of the pack
	"Highlight", -- allowed viewers only: who to outline
	"AbilityState", -- own cooldowns
	"HideChanged", -- own hiding spot
	"RoleOptions", -- own usable roles for the role-selection screen
	"RolePicksAck", -- own accepted picks
	"DashStart", -- own dash (the client moves its own character)
	"TaskChanged", -- own task of the day
	"Scoreboard", -- game over: everyone's role (public once the game is over)
	"LikeCounts", -- likes per player on the scoreboard
	"Results", -- the MVP
	"RewardSummary", -- own reward
	-- Lobby place
	"PadsChanged", -- every pad's count and state (public)
	"QueueChanged", -- own pad: am I in a queue, am I the host
	"LobbyNotice", -- a short message for one player
	"Effect", -- visual feedback: shot tracers (everyone), "blocked" / "blessed" (the people involved)
	-- client -> server
	"RequestSync",
	"VoteSelect",
	"VoteConfirm",
	"WolfAttack",
	"WolfAbility",
	"HideExit",
	"RolePicks",
	"AbilityUse",
	"ItemUse",
	"Like",
	"StartRequest", -- lobby: the host starts the match
}

function Remotes.createAll()
	assert(RunService:IsServer(), "Remotes.createAll is server-only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in Remotes.Names do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.get(name: string): RemoteEvent
	assert(table.find(Remotes.Names, name), `unknown remote "{name}"`)
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
