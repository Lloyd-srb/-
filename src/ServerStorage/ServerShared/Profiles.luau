--!strict
--[[
	Profiles — every player's saved data, in a DataStore, with session locking.
	Used by both places (Lobby and Match).

	Session locking: the saved record is { Data = <profile>, Session = { Job,
	Place, At } }. A server only loads a profile when no other server holds
	it (or the other server's lock is stale = it crashed), and only writes
	while it still holds the lock. So one player's data is never open on two
	servers at once, and nothing is ever given twice.

	  - Join: take the lock. If the server the player just came from has not
	    let go yet, try again every Config.Data.LoadRetryDelay seconds; after
	    Config.Data.LoadTimeout take the lock over (that server stops saving).
	  - Every Config.Data.AutoSaveInterval: save and renew the lock.
	  - Leave / server shutdown (BindToClose): save and let go.
	  - Every DataStore call is retried with growing waits (1, 2, 4, 8 s).
	  - If the DataStore cannot be reached at all (or Studio has no API
	    access), the player gets a temporary profile: they can play, nothing
	    is saved, and Robux purchases wait until the data is back.

	Services change a profile only through Profiles.Update(), which marks it
	for saving and fires Profiles.Changed.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

local ProfileLogic = require(script.Parent.Logic.ProfileLogic)

type Session = {
	Player: Player,
	Data: ProfileLogic.Data,
	Temporary: boolean, -- never saved (DataStore unreachable)
	Released: boolean, -- lock given up (or lost): no more saving
	Dirty: boolean,
	Saving: boolean,
}

local KICK_LOST_LOCK = "Your data was opened on another server. Please rejoin.\n"
	.. "ข้อมูลของคุณถูกเปิดจากเซิร์ฟเวอร์อื่น กรุณาเข้าเกมใหม่"
local CLOSE_TIMEOUT = 25 -- seconds Roblox gives BindToClose is 30

local Profiles = {}

Profiles.Loaded = Signal.new() -- (player, data)
Profiles.Changed = Signal.new() -- (player, data)

local sessions: { [number]: Session } = {}
local loading: { [number]: boolean } = {}
local store: any = nil
local sessionId = ""
local started = false

local function key(userId: number): string
	return Config.Data.KeyPrefix .. tostring(userId)
end

-- Calls `call` until it works, waiting 1, 2, 4... seconds in between.
local function attempt(what: string, call: () -> any): boolean
	local tries = if RunService:IsStudio() then 1 else Config.Data.MaxAttempts
	local lastError: any = nil
	for index = 1, tries do
		local ok, err = pcall(call)
		if ok then
			return true
		end
		lastError = err
		if index < tries then
			task.wait(2 ^ (index - 1))
		end
	end
	warn(`[Profiles] {what} failed: {tostring(lastError)}`)
	return false
end

local placeId = 0

local function lockRecord(): { [string]: any }
	return { Job = sessionId, Place = placeId, At = os.time() }
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

-- Tries to take the lock. Returns "Ok" (+ the saved data), "Locked" or "Error".
local function tryLock(userId: number, force: boolean): (string, any)
	local outcome, saved = "Locked", nil
	local ok = attempt("loading " .. key(userId), function()
		return store:UpdateAsync(key(userId), function(old: any): any
			local record = if type(old) == "table" then old else {}
			local lock = record.Session
			local free = type(lock) ~= "table"
				or lock.Job == sessionId
				or type(lock.At) ~= "number"
				or os.time() - lock.At > Config.Data.LockStaleAfter
			if not free and not force then
				outcome = "Locked"
				return nil -- leave the record alone
			end
			outcome, saved = "Ok", record.Data
			return { Data = record.Data, Session = lockRecord() }
		end)
	end)
	if not ok then
		return "Error", nil
	end
	return outcome, saved
end

-- Writes the profile. `release` gives the lock up. Returns true when saved.
local function save(session: Session, release: boolean): boolean
	while session.Saving do
		task.wait(0.1)
	end
	if session.Temporary or session.Released then
		return false
	end
	session.Saving = true
	session.Dirty = false
	local lost = false
	local userId = session.Player.UserId
	local ok = attempt("saving " .. key(userId), function()
		return store:UpdateAsync(key(userId), function(old: any): any
			local lock = if type(old) == "table" then old.Session else nil
			if type(lock) == "table" and lock.Job ~= sessionId then
				lost = true -- another server took it over: do not overwrite its data
				return nil
			end
			lost = false
			return { Data = session.Data, Session = if release then nil else lockRecord() }
		end)
	end)
	session.Saving = false
	if not ok then
		session.Dirty = true
		return false
	end
	if lost then
		session.Released = true
		warn(`[Profiles] {key(userId)} is open on another server; this server stopped saving it`)
		if session.Player.Parent then
			session.Player:Kick(KICK_LOST_LOCK)
		end
		return false
	end
	if release then
		session.Released = true
	end
	return true
end

local function load(player: Player)
	local userId = player.UserId
	-- Rejoined this same server at once: let the old session finish saving.
	while sessions[userId] and sessions[userId].Player ~= player do
		if not player.Parent then
			return
		end
		task.wait(0.2)
	end
	if sessions[userId] or loading[userId] then
		return
	end
	loading[userId] = true
	local startedAt = os.clock()
	local data: ProfileLogic.Data
	local temporary = false
	while true do
		if store == nil then
			data, temporary = ProfileLogic.template(), true
			break
		end
		local force = os.clock() - startedAt >= Config.Data.LoadTimeout
		local outcome, saved = tryLock(userId, force)
		if outcome == "Ok" then
			data = ProfileLogic.reconcile(saved)
			break
		elseif outcome == "Error" then
			data, temporary = ProfileLogic.template(), true
			break
		end
		if not player.Parent then
			loading[userId] = nil
			return
		end
		task.wait(Config.Data.LoadRetryDelay)
	end
	loading[userId] = nil

	local session: Session = {
		Player = player,
		Data = data,
		Temporary = temporary,
		Released = false,
		Dirty = false,
		Saving = false,
	}
	if not player.Parent then
		save(session, true) -- left while loading: give the lock back
		return
	end
	if temporary then
		warn(`[Profiles] {player.Name} plays with a temporary profile (nothing will be saved)`)
	end
	sessions[userId] = session
	Profiles.Loaded:Fire(player, data)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

-- The player's profile, or nil while it is still loading.
function Profiles.Get(player: Player): ProfileLogic.Data?
	local session = sessions[player.UserId]
	return if session and session.Player == player then session.Data else nil
end

-- Waits (up to `timeout` seconds) for the profile to load.
function Profiles.WaitFor(player: Player, timeout: number?): ProfileLogic.Data?
	local deadline = os.clock() + (timeout or Config.Data.LoadTimeout + 10)
	while player.Parent and os.clock() < deadline do
		local data = Profiles.Get(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return Profiles.Get(player)
end

-- True when this player's progress cannot be saved right now.
function Profiles.IsTemporary(player: Player): boolean
	local session = sessions[player.UserId]
	return session == nil or session.Temporary or session.Released
end

-- Changes a profile. Returns false if it is not loaded.
function Profiles.Update(player: Player, change: (ProfileLogic.Data) -> ()): boolean
	local session = sessions[player.UserId]
	if not session or session.Player ~= player or session.Released then
		return false
	end
	change(session.Data)
	session.Dirty = true
	Profiles.Changed:Fire(player, session.Data)
	return true
end

-- Saves now (purchases must be on disk before Roblox is told "granted").
function Profiles.SaveNow(player: Player): boolean
	local session = sessions[player.UserId]
	if not session or session.Player ~= player then
		return false
	end
	return save(session, false)
end

--------------------------------------------------------------------------------

function Profiles.Init()
	-- pcall: the offline test tools have no JobId / PlaceId; Roblox always does.
	local okJob, jobId = pcall(function()
		return game.JobId
	end)
	local okPlace, place = pcall(function()
		return game.PlaceId
	end)
	placeId = if okPlace and type(place) == "number" then place else 0
	sessionId = if okJob and type(jobId) == "string" and jobId ~= ""
		then jobId
		else "studio-" .. tostring(Random.new():NextInteger(1, 2 ^ 30))
	local name = if RunService:IsStudio() then Config.Data.StudioStoreName else Config.Data.StoreName
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		store = result
	else
		warn(`[Profiles] no DataStore ({tostring(result)}): profiles will not be saved. `
			.. "In Studio: Game Settings > Security > Enable Studio Access to API Services.")
	end
end

function Profiles.Start()
	if started then
		return -- both a place's bootstrap and a service may start it
	end
	started = true

	Players.PlayerAdded:Connect(function(player: Player)
		load(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		-- Deferred: other services first give the leaving player what they
		-- earned (e.g. match rewards), then the profile is saved and let go.
		task.defer(function()
			local session = sessions[player.UserId]
			if session and session.Player == player then
				save(session, true)
				if sessions[player.UserId] == session then
					sessions[player.UserId] = nil
				end
			end
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Data.AutoSaveInterval)
			for _, session in sessions do
				if not session.Released and not session.Temporary then
					-- Also when nothing changed: the save renews the lock.
					task.spawn(save, session, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for _, session in sessions do
			pending += 1
			task.spawn(function()
				save(session, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + CLOSE_TIMEOUT
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return Profiles
