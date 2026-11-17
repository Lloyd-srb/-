--!strict
--[[
	MovementGuard — keeps players honest about where they are (owner,
	17 Nov 2026), and notices who is doing something (the AFK rule).

	On Roblox each player's own computer moves their character, so a
	modified client can run faster than allowed or jump across the map.
	Twice a second the server compares every living player's position with
	the last one: if they went further than their current speed allows
	(with some slack for lag), they are put back where they were.

	The game itself moves people too (night warp into houses, morning warp,
	the meeting, hiding, revives, the Bodyguard's dash). Those moves go
	through MovementGuard.Warp / MovementGuard.Allow so they are never
	mistaken for cheating. Only horizontal distance is checked: falling and
	jumping are left alone. Bots and ghosts are not checked.

	Every real step a player takes also counts as activity for the AFK rule
	(MatchService.MarkActive).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Roster = require(script.Parent.Parent.Logic.Roster)

local MatchService = require(script.Parent.MatchService)
local MoveService = require(script.Parent.MoveService)

type Track = {
	Last: Vector3, -- last position accepted
	At: number, -- os.clock() of that position
	GraceUntil: number, -- no checks before this (a move made by the game)
	Speed: number, -- allowed speed at the last check
}

local MovementGuard = {}

MovementGuard.Corrections = 0 -- how many times someone was put back (for tests / logs)

local tracks: { [number]: Track } = {}

local function checking(): boolean
	local cfg = Config.AntiCheat
	-- Studio testers teleport around on purpose: off there unless asked for.
	return cfg.Enabled and (not Config.Debug.Enabled or cfg.InStudio)
end

local function reset(id: number, position: Vector3, grace: number)
	tracks[id] = {
		Last = position,
		At = os.clock(),
		GraceUntil = os.clock() + grace,
		Speed = MoveService.Speed(id),
	}
end

-- Moves a member's character for the game (warps). Never counted as cheating.
function MovementGuard.Warp(id: number, target: CFrame)
	local character = MatchService.CharacterOf(id)
	if character then
		character:PivotTo(target)
	end
	reset(id, target.Position, Config.AntiCheat.WarpGrace)
end

-- Lets a member move freely for a few seconds (e.g. the Bodyguard's dash).
function MovementGuard.Allow(id: number, seconds: number)
	local track = tracks[id]
	if track then
		track.GraceUntil = math.max(track.GraceUntil, os.clock() + seconds)
	end
end

local function check()
	local cfg = Config.AntiCheat
	local now = os.clock()
	for _, member in Roster.alive(MatchService.Roster) do
		local root = if member.IsBot then nil else MatchService.RootOf(member.Id)
		if not root then
			tracks[member.Id] = nil
			continue
		end
		local position = root.CFrame.Position
		local track = tracks[member.Id]
		if not track or root.Anchored then
			-- First sighting, or parked while hiding: start again from here.
			reset(member.Id, position, 0)
			continue
		end
		local step = Vector3.new(position.X - track.Last.X, 0, position.Z - track.Last.Z).Magnitude
		local inGrace = now < track.GraceUntil
		if step >= Config.Afk.MoveStuds and not inGrace then
			MatchService.MarkActive(member.Id)
		end
		local speedNow = MoveService.Speed(member.Id)
		if inGrace or not checking() then
			track.Last, track.At, track.Speed = position, now, speedNow
			continue
		end
		local allowed = math.max(track.Speed, speedNow) * (now - track.At) * cfg.Tolerance + cfg.Slack
		if step > allowed then
			-- Too far, too fast: back to the last accepted spot.
			MovementGuard.Corrections += 1
			warn(`[MovementGuard] {member.Name} moved {math.floor(step)} studs (allowed {math.floor(allowed)}): put back`)
			local character = MatchService.CharacterOf(member.Id)
			if character then
				character:PivotTo(CFrame.new(track.Last + Vector3.new(0, 0.5, 0)))
			end
			track.At, track.Speed = now, speedNow
		else
			track.Last, track.At, track.Speed = position, now, speedNow
		end
	end
end

function MovementGuard.Init() end

function MovementGuard.Start()
	-- A new body starts a new track (revive, respawn after a glitch, match start).
	local function forget(member: Roster.Member)
		tracks[member.Id] = nil
	end
	MatchService.BodyReplaced:Connect(forget)
	MatchService.MemberRevived:Connect(forget)
	MatchService.MemberDied:Connect(forget)
	MatchService.MatchStarted:Connect(function()
		table.clear(tracks)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AntiCheat.Interval)
			if MatchService.Started and not MatchService.Winner then
				check()
			end
		end
	end)
end

return MovementGuard
