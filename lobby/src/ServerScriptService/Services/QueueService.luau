--!strict
--[[
	QueueService — the four 12-seat queue pads of the lobby (owner's rules,
	17 Nov 2026; the rules themselves are in Logic.PadQueue).

	Players join a queue by standing on its glowing pad and leave by stepping
	off. The host (first in) gets a Start button once 8+ are in. A full pad
	counts down 10 s and holds everyone in place. Then the whole queue is
	teleported to a fresh reserved Match server, which is told how many
	players to expect.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)

local PadQueue = require(script.Parent.Parent.Logic.PadQueue)

local Net = require(game:GetService("ServerStorage"):WaitForChild("ServerShared"):WaitForChild("Net"))

type PadEntry = { State: PadQueue.Pad, Part: BasePart }

local STAND_HEIGHT = 8 -- how far above the pad still counts as standing on it
local HUMAN_SPEED = 16
local HUMAN_JUMP = 50

local QueueService = {}

QueueService.Pads = {} :: { [number]: PadEntry }
local padOf: { [number]: number } = {} -- UserId -> pad id
local frozen: { [number]: boolean } = {}
local lastSnapshot = ""

--------------------------------------------------------------------------------
-- Who stands where
--------------------------------------------------------------------------------

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function padAt(position: Vector3): number?
	for id, entry in QueueService.Pads do
		local part = entry.Part
		local localPoint = part.CFrame:PointToObjectSpace(position)
		local top = part.Size.Y / 2
		if
			math.abs(localPoint.X) <= part.Size.X / 2
			and math.abs(localPoint.Z) <= part.Size.Z / 2
			and localPoint.Y >= top - 1
			and localPoint.Y <= top + STAND_HEIGHT
		then
			return id
		end
	end
	return nil
end

local function setFrozen(player: Player, freeze: boolean)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if freeze then
		frozen[player.UserId] = true
	else
		frozen[player.UserId] = nil
	end
	humanoid.WalkSpeed = if freeze then 0 else HUMAN_SPEED
	humanoid.JumpPower = if freeze then 0 else HUMAN_JUMP
end

--------------------------------------------------------------------------------
-- Telling the players
--------------------------------------------------------------------------------

local function serverTime(clockTime: number?): number?
	if not clockTime then
		return nil
	end
	return workspace:GetServerTimeNow() + (clockTime - os.clock())
end

local function hostName(pad: PadQueue.Pad): string?
	local host = PadQueue.host(pad)
	local player = if host then Players:GetPlayerByUserId(host) else nil
	return if player then player.DisplayName else nil
end

local function snapshot(): { any }
	local list = {}
	for id = 1, Config.Lobby.PadCount do
		local entry = QueueService.Pads[id]
		if entry then
			local pad = entry.State
			table.insert(list, {
				Id = id,
				Count = #pad.Members,
				Max = Config.Match.MaxPlayers,
				Min = Config.Match.MinPlayers,
				State = PadQueue.state(pad),
				CountdownEndsAt = serverTime(pad.CountdownEndsAt),
				StartsAt = serverTime(pad.AutoStartAt),
				HostName = hostName(pad),
			})
		end
	end
	return list
end

local function tellMembers(entry: PadEntry)
	local pad = entry.State
	for _, id in pad.Members do
		local player = Players:GetPlayerByUserId(id)
		if player then
			Net.fire(player, "QueueChanged", {
				PadId = pad.Id,
				IsHost = PadQueue.host(pad) == id,
				CanStart = PadQueue.host(pad) == id and PadQueue.state(pad) ~= "Waiting" and not pad.Launching,
			})
		end
	end
end

local function broadcast()
	local list = snapshot()
	local key = ""
	for _, pad in list do
		key ..= string.format("%d:%d:%s:%s;", pad.Id, pad.Count, pad.State, tostring(pad.HostName))
	end
	if key ~= lastSnapshot then
		lastSnapshot = key
		Net.fireAll("PadsChanged", list)
		for _, entry in QueueService.Pads do
			tellMembers(entry)
		end
	end
end

local function leaveQueue(player: Player)
	padOf[player.UserId] = nil
	Net.fire(player, "QueueChanged", { PadId = 0, IsHost = false, CanStart = false })
end

--------------------------------------------------------------------------------
-- Launching a match
--------------------------------------------------------------------------------

local function notify(ids: { number }, key: string)
	for _, id in ids do
		local player = Players:GetPlayerByUserId(id)
		if player then
			Net.fire(player, "LobbyNotice", { Key = key })
		end
	end
end

local function unfreeze(ids: { number })
	for _, id in ids do
		local player = Players:GetPlayerByUserId(id)
		if player and frozen[id] then
			setFrozen(player, false)
		end
	end
end

-- A fresh reserved (private) Match server for this queue, told who is coming.
local function teleport(placeId: number, party: { Player }, data: { [string]: any }): boolean
	local ok, err = pcall(function()
		local accessCode = TeleportService:ReserveServer(placeId)
		TeleportService:TeleportToPrivateServer(placeId, accessCode, party, nil, data)
	end)
	if not ok then
		warn("[QueueService] teleport failed: " .. tostring(err))
	end
	return ok
end

local function launch(entry: PadEntry)
	local pad = entry.State
	local ids = PadQueue.launch(pad)
	local party: { Player } = {}
	for _, id in ids do
		local player = Players:GetPlayerByUserId(id)
		if player then
			table.insert(party, player)
			setFrozen(player, true)
		end
	end
	broadcast()

	local placeId = Config.Places.MatchPlaceId
	if RunService:IsStudio() or placeId == 0 then
		-- Teleports cannot happen in Studio (and need the Match place id).
		notify(ids, "Lobby.NoTeleport")
		task.delay(3, function()
			unfreeze(ids)
			for _, id in ids do
				local player = Players:GetPlayerByUserId(id)
				if player then
					leaveQueue(player)
				end
			end
			PadQueue.reset(pad)
			broadcast()
		end)
		return
	end

	task.spawn(function()
		local data = { Expected = #party, Party = ids }
		local ok = false
		for attempt = 1, Config.Lobby.LaunchAttempts do
			ok = teleport(placeId, party, data)
			if ok then
				break
			end
			task.wait(2 * attempt)
		end
		if not ok then
			notify(ids, "Lobby.TeleportFailed")
			unfreeze(ids)
			PadQueue.release(pad, os.clock())
			broadcast()
			return
		end
		-- Whoever is still here after a while did not make it: open the pad again.
		task.wait(Config.Lobby.ReturnCheck)
		local stayed: { number } = {}
		for _, id in pad.Members do
			if Players:GetPlayerByUserId(id) then
				table.insert(stayed, id)
			end
		end
		unfreeze(stayed)
		for _, id in stayed do
			local player = Players:GetPlayerByUserId(id)
			if player then
				leaveQueue(player)
			end
		end
		if #stayed > 0 then
			notify(stayed, "Lobby.TeleportFailed")
		end
		PadQueue.reset(pad)
		broadcast()
	end)
end

--------------------------------------------------------------------------------

local function step()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local current = padOf[player.UserId]
		local standing = if root then padAt(root.CFrame.Position) else nil
		if standing and not current then
			local entry = QueueService.Pads[standing]
			if PadQueue.join(entry.State, player.UserId) then
				padOf[player.UserId] = standing
			end
		elseif current and standing ~= current then
			local entry = QueueService.Pads[current]
			if PadQueue.leave(entry.State, player.UserId) then
				leaveQueue(player)
			end
		end
	end
	for _, entry in QueueService.Pads do
		local pad = entry.State
		local launchNow = PadQueue.tick(pad, now)
		-- A full pad holds everyone in place for the countdown (a new body
		-- after a respawn too).
		if pad.CountdownEndsAt then
			for _, id in pad.Members do
				local player = Players:GetPlayerByUserId(id)
				local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if player and (not frozen[id] or (humanoid and humanoid.WalkSpeed ~= 0)) then
					setFrozen(player, true)
				end
			end
		end
		if launchNow then
			launch(entry)
		end
	end
	-- Nobody stays frozen once their pad is no longer locked (e.g. the
	-- countdown stopped because too many players quit).
	for id in table.clone(frozen) do
		local current = padOf[id]
		local entry = if current then QueueService.Pads[current] else nil
		if not entry or not PadQueue.isLocked(entry.State) then
			local player = Players:GetPlayerByUserId(id)
			if player then
				setFrozen(player, false)
			else
				frozen[id] = nil
			end
		end
	end
	broadcast()
end

local function onStartRequest(player: Player)
	local current = padOf[player.UserId]
	local entry = if current then QueueService.Pads[current] else nil
	if entry and PadQueue.requestStart(entry.State, player.UserId) then
		launch(entry)
	end
end

function QueueService.Init()
	for _, part in CollectionService:GetTagged("QueuePad") do
		local id = part:GetAttribute("PadId")
		if part:IsA("BasePart") and type(id) == "number" then
			QueueService.Pads[id] = { State = PadQueue.new(id), Part = part }
		end
	end
	if next(QueueService.Pads) == nil then
		warn("[QueueService] no queue pads: run build/lobby/BuildLobby.luau in Studio")
	end
end

function QueueService.Start()
	Net.on("StartRequest", onStartRequest, 4, 5)

	Players.PlayerAdded:Connect(function(player: Player)
		lastSnapshot = "" -- the newcomer gets the current pads
		broadcast()
		Net.fire(player, "PadsChanged", snapshot())
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local current = padOf[player.UserId]
		padOf[player.UserId] = nil
		frozen[player.UserId] = nil
		if current then
			PadQueue.leave(QueueService.Pads[current].State, player.UserId, true)
		end
	end)

	task.spawn(function()
		while true do
			step()
			task.wait(Config.Lobby.ScanInterval)
		end
	end)
end

return QueueService
