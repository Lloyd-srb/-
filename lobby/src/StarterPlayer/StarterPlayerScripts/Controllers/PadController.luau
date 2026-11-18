--!strict
--[[
	PadController — the lobby's queue pads, as this player sees them:
	the sign over each pad (count / state, in the player's language), and at
	the bottom of the screen this player's own queue with the host's Start
	button. The server decides everything; this only shows it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PadController = {}

local NOTICE_SECONDS = 6

local pads: { [number]: any } = {}
local mine = { PadId = 0, IsHost = false, CanStart = false }
local notice = "" -- e.g. "could not reach the village", kept on screen for a while
local noticeUntil = 0

local panel: Frame
local statusLabel: TextLabel
local hintLabel: TextLabel
local startButton: TextButton

local function secondsLeft(pad: any): number
	local endsAt = if type(pad.CountdownEndsAt) == "number" then pad.CountdownEndsAt else pad.StartsAt
	if type(endsAt) ~= "number" then
		return 0
	end
	return math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
end

local function stateText(pad: any): string
	if pad.State == "Launching" then
		return Loc.format("Lobby.Launching")
	elseif pad.State == "Countdown" then
		return Loc.format("Lobby.Countdown", { seconds = secondsLeft(pad) })
	elseif pad.State == "Ready" then
		return Loc.format("Lobby.Ready", { name = pad.HostName or "?", seconds = secondsLeft(pad) })
	end
	return Loc.format("Lobby.Waiting", { min = pad.Min })
end

local function sign(id: number): SurfaceGui?
	local lobby = workspace:FindFirstChild("Lobby")
	local folder = lobby and lobby:FindFirstChild("Pads")
	local board = folder and folder:FindFirstChild("PadSign" .. id)
	local gui = board and board:FindFirstChild("Sign")
	return if gui and gui:IsA("SurfaceGui") then gui else nil
end

local function render()
	for id, pad in pads do
		local gui = sign(id)
		if gui then
			(gui:FindFirstChild("Title") :: TextLabel).Text = Loc.format("Lobby.PadTitle", { id = id });
			(gui:FindFirstChild("Count") :: TextLabel).Text = string.format("%d/%d", pad.Count, pad.Max);
			(gui:FindFirstChild("Status") :: TextLabel).Text = stateText(pad)
		end
	end

	local pad = pads[mine.PadId]
	local showNotice = os.clock() < noticeUntil
	panel.Visible = pad ~= nil or showNotice
	if not pad then
		-- Out of the queue (e.g. the trip failed): only the notice is shown.
		statusLabel.Text = ""
		hintLabel.Text = if showNotice then notice else ""
		startButton.Visible = false
		return
	end
	local status = Loc.format("Lobby.InQueue", { id = mine.PadId, count = pad.Count, max = pad.Max })
	if pad.State == "Countdown" or pad.State == "Launching" then
		status = stateText(pad)
	end
	statusLabel.Text = status
	if pad.State == "Countdown" or pad.State == "Launching" then
		hintLabel.Text = Loc.format("Lobby.Locked")
	elseif mine.IsHost then
		hintLabel.Text = Loc.format("Lobby.YouAreHost") .. "  ·  " .. stateText(pad)
	else
		hintLabel.Text = Loc.format("Lobby.StepOff")
	end
	if showNotice then
		hintLabel.Text = notice
	end
	startButton.Visible = mine.CanStart
end

function PadController.Start()
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("QueueUI")
	panel = gui:WaitForChild("Panel") :: Frame
	statusLabel = panel:WaitForChild("StatusLabel") :: TextLabel
	hintLabel = panel:WaitForChild("HintLabel") :: TextLabel
	startButton = panel:WaitForChild("StartButton") :: TextButton
	startButton.Text = Loc.format("Lobby.Start")
	startButton.Activated:Connect(function()
		Remotes.get("StartRequest"):FireServer()
	end)

	Remotes.get("PadsChanged").OnClientEvent:Connect(function(list: any)
		if type(list) ~= "table" then
			return
		end
		for _, pad in list do
			if type(pad) == "table" and type(pad.Id) == "number" then
				pads[pad.Id] = pad
			end
		end
		render()
	end)
	Remotes.get("QueueChanged").OnClientEvent:Connect(function(data: any)
		if type(data) == "table" and type(data.PadId) == "number" then
			mine = { PadId = data.PadId, IsHost = data.IsHost == true, CanStart = data.CanStart == true }
			render()
		end
	end)
	Remotes.get("LobbyNotice").OnClientEvent:Connect(function(data: any)
		if type(data) == "table" and type(data.Key) == "string" then
			-- Kept for a few seconds: the pad updates that follow would
			-- otherwise overwrite it at once.
			notice = Loc.format(data.Key)
			noticeUntil = os.clock() + NOTICE_SECONDS
			render()
		end
	end)

	-- The countdown ticks on screen between server updates; a notice runs out.
	local last = 0
	local noticeShown = false
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - last >= 0.25 then
			last = now
			local noticeNow = now < noticeUntil
			local needed = noticeNow ~= noticeShown
			noticeShown = noticeNow
			for _, pad in pads do
				if pad.State == "Countdown" or pad.State == "Ready" then
					needed = true
					break
				end
			end
			if needed then
				render()
			end
		end
	end)
end

return PadController
