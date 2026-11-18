--!strict
--[[
	EndService — the end of a match (GDD §7, §13).

	Game over:
	  1. The scoreboard is sent to everyone: every player's role is revealed.
	  2. For Config.Timers.LikeWindow seconds players can give their one like
	     to someone else. Most likes = MVP (+20% reward).
	  3. Rewards are worked out (nights survived, win / lose, Killer / Fool
	     bonus, tasks, MVP) and added to each player's profile; each player
	     sees their own.
	  4. When the scoreboard time is over, everyone goes back to the lobby
	     (milestone 8 sets the lobby place id).

	A player who leaves before the end keeps the reward for the nights they
	survived, counted as a loss unless the result is already known.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PhaseMachine = require(ReplicatedStorage.Shared.Logic.PhaseMachine)

local Logic = script.Parent.Parent.Logic
local Likes = require(Logic.Likes)
local Rewards = require(Logic.Rewards)
local Roster = require(Logic.Roster)
local WinConditions = require(Logic.WinConditions)

local MatchService = require(script.Parent.MatchService)
local Net = require(script.Parent.Net)
local ProfileService = require(script.Parent.ProfileService)
local RoundService = require(script.Parent.RoundService)
local Travel = require(script.Parent.Travel)

export type Summary = {
	Coins: number,
	Exp: number,
	PassExp: number,
	MasteryRole: string,
	MasteryPoints: number,
	Diamonds: number,
	Won: boolean,
	NightsSurvived: number,
	TasksCompleted: number,
	IsMvp: boolean,
}

local EndService = {}

-- What each player was given (kept for checks and for the profile save in milestone 9).
EndService.Granted = {} :: { [number]: Summary }
EndService.Forfeited = {} :: { [number]: boolean } -- left while alive: no reward

local likes = Likes.new()
local likesOpen = false
local mvpId: number? = nil
local random = Random.new()

local function scaled(seconds: number): number
	return seconds * (if Config.Debug.Enabled then Config.Debug.TimerScale else 1)
end

local function didWin(member: Roster.Member): boolean
	local winner = MatchService.Winner
	return winner ~= nil and WinConditions.didWin(member.Faction, winner :: any)
end

local function scoreboard(): { any }
	local rows = {}
	for _, member in Roster.list(MatchService.Roster) do
		table.insert(rows, {
			Id = member.Id,
			Name = member.Name,
			IsBot = member.IsBot,
			Role = if member.IsPup then "Pup" else member.Role,
			StartRole = member.StartRole,
			Faction = member.Faction,
			Alive = member.Alive,
			Won = didWin(member),
		})
	end
	return rows
end

-- Array form: remote arguments must not use sparse numeric keys.
local function countsPayload(): { any }
	local list = {}
	for id, count in Likes.counts(likes) do
		table.insert(list, { Id = id, Count = count })
	end
	return list
end

-- Works out and grants one player's reward (once).
local function grant(member: Roster.Member, player: Player)
	if EndService.Granted[member.Id] or EndService.Forfeited[member.Id] or member.IsBot then
		return
	end
	local won = didWin(member)
	local isMvp = mvpId == member.Id
	local reward = Rewards.compute({
		NightsSurvived = member.NightsSurvived,
		Won = won,
		Faction = member.Faction,
		TasksCompleted = member.TasksCompleted,
		IsMvp = isMvp,
	})
	local diamonds = ProfileService.Grant(player, {
		Coins = reward.Coins,
		Exp = reward.Exp,
		PassExp = reward.PassExp,
		MasteryRole = member.StartRole,
		MasteryPoints = reward.MasteryPoints,
	})
	local summary: Summary = {
		Coins = reward.Coins,
		Exp = reward.Exp,
		PassExp = reward.PassExp,
		MasteryRole = member.StartRole,
		MasteryPoints = reward.MasteryPoints,
		Diamonds = diamonds,
		Won = won,
		NightsSurvived = member.NightsSurvived,
		TasksCompleted = member.TasksCompleted,
		IsMvp = isMvp,
	}
	EndService.Granted[member.Id] = summary
	if player.Parent then
		Net.fire(player, "RewardSummary", summary)
	end
end

local function onLike(player: Player, target: any)
	if not likesOpen or type(target) ~= "number" then
		return
	end
	local voter = MatchService.MemberOf(player)
	if not voter or MatchService.Roster.Members[target] == nil then
		return
	end
	if Likes.give(likes, voter.Id, target) then
		Net.fireAll("LikeCounts", countsPayload())
	end
end

-- Back to the lobby. In Studio teleports do not work.
local function sendHome()
	Travel.sendEveryoneHome()
end

local function closeLikes()
	likesOpen = false
	mvpId = Rewards.pickMvp(Likes.counts(likes), function(tied: { number }): number
		return tied[random:NextInteger(1, #tied)]
	end)
	if not mvpId then
		-- [owner] 18 Nov 2026: nobody gave a like = a random player (not a bot,
		-- not someone who left while alive).
		local pool: { number } = {}
		for _, member in Roster.list(MatchService.Roster) do
			if not member.IsBot and not EndService.Forfeited[member.Id] and MatchService.PlayerOf(member.Id) then
				table.insert(pool, member.Id)
			end
		end
		if #pool > 0 then
			mvpId = pool[random:NextInteger(1, #pool)]
		end
	end
	Net.fireAll("Results", { MvpId = mvpId })
	for _, player in Players:GetPlayers() do
		local member = MatchService.MemberOf(player)
		if member then
			grant(member, player)
		end
	end
end

local function onGameOver()
	likesOpen = true
	Net.fireAll("Scoreboard", { Winner = MatchService.Winner, Rows = scoreboard() })
	Net.fireAll("LikeCounts", countsPayload())
	task.delay(scaled(Config.Timers.LikeWindow), function()
		closeLikes()
		task.delay(scaled(Config.Timers.GameOverScoreboard - Config.Timers.LikeWindow), sendHome)
	end)
end

function EndService.Init() end

-- A ghost, a spectator, or anyone once the game is over may go back to the
-- lobby at once (owner, 17 Nov 2026). The living must play on.
local function onBackToLobby(player: Player)
	local member = MatchService.MemberOf(player)
	if member and member.Alive and not MatchService.Winner then
		return
	end
	if not Travel.toLobby({ player }) then
		Net.fire(player, "Announcement", { Key = "Hud.NoLobbyTeleport" })
	end
end

function EndService.Start()
	Net.on("Like", onLike, 10, 5)
	Net.on("BackToLobby", onBackToLobby, 2, 10)

	RoundService.PhaseStarted:Connect(function(state: PhaseMachine.PhaseState)
		if state.Phase == "GameOver" then
			onGameOver()
		end
	end)

	-- Leaving early: a ghost keeps what was earned so far (GDD §12); a player
	-- who leaves while still alive gets nothing ([owner] 18 Nov 2026).
	-- MatchService (started first) has already marked them dead with "Left".
	Players.PlayerRemoving:Connect(function(player: Player)
		local member = MatchService.MemberOf(player)
		if not MatchService.Started or not member then
			return
		end
		if member.DeathCause == "Left" and not MatchService.Winner then
			EndService.Granted[member.Id] = nil
			EndService.Forfeited[member.Id] = true
			return
		end
		grant(member, player)
	end)

	MatchService.SyncRequested:Connect(function(player: Player)
		if MatchService.Winner and RoundService.State.Phase == "GameOver" then
			Net.fire(player, "Scoreboard", { Winner = MatchService.Winner, Rows = scoreboard() })
			Net.fire(player, "LikeCounts", countsPayload())
			if not likesOpen then
				Net.fire(player, "Results", { MvpId = mvpId })
			end
		end
	end)
end

return EndService
