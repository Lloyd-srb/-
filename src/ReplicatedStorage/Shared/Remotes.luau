--!strict
--[[
	Remotes — the single list of RemoteEvents. The server creates them once
	(Remotes.createAll); clients wait for them (Remotes.get).

	Server -> one client only (secret):  RoleAssigned, HouseAssigned, VoteMine,
	                                     FormChanged, PackChanged, Highlight,
	                                     AbilityState, HideChanged
	Server -> everyone (public):         PhaseChanged, Announcement, RosterChanged,
	                                     VoteOpened, VoteCounts, VoteClosed, GameOver
	Client -> server (intents):          RequestSync, VoteSelect, VoteConfirm,
	                                     WolfAttack, WolfAbility, HideExit
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
	"EyesClosed", -- the screen goes black for a moment (night / morning move home)
	"HouseAssigned",
	"VoteOpened",
	"VoteCounts",
	"VoteMine",
	"VoteClosed",
	"VoteLocked", -- the last seconds of the meeting: no more changes (owner, 17 Nov 2026)
	"GameOver",
	"FormChanged", -- "Human" | "Wolf" | "Pup" (own form)
	"PackChanged", -- wolf side only: ids of the pack
	"Highlight", -- allowed viewers only: who to outline
	"AbilityState", -- own cooldowns
	"HideChanged", -- own hiding spot
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
	"Sound", -- a sound to play: { Key, At? } (world sounds only to players close by)
	"ProfileView", -- own coins, diamonds, level, owned things, pass, spins (Lobby)
	"ShopResult", -- own purchase / equip result
	"SpinResult", -- own Daily Spin prize
	"CodeResult", -- own code result
	"Effect", -- visual feedback: shot tracers (everyone), "blocked" / "blessed" (the people involved)
	-- client -> server
	"RequestSync",
	"VoteSelect",
	"VoteConfirm",
	"WolfAttack",
	"WolfAbility",
	"HideExit",
	"SaveRolePicks", -- Lobby: the 3 roles this player wants (owner, 18 Nov 2026)
	"SelectMonster", -- Lobby: the monster to play when dealt the wolf (owner, 19 Nov 2026)
	"ShopBuy", -- Lobby: buy (kind, id, currency)
	"Equip", -- Lobby: wear a skin / title (slot, id or "")
	"SpinRequest", -- Lobby: use a Daily Spin
	"CodeRedeem", -- Lobby: redeem a code (text)
	"TutorialDone", -- Lobby: the player read the how-to-play pages
	"BackToLobby", -- Match: a ghost / spectator / anyone after the end goes back
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
