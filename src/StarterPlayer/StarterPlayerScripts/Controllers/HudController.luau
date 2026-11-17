--!strict
--[[
	HudController — phase name, countdown, own role, announcements and the
	ending text. Pure presentation: everything shown comes from server events.
	The ScreenGui is built by build/BuildUI.luau (StarterGui.Hud).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Loc = require(ReplicatedStorage.Shared.Loc)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ClientState = require(script.Parent.ClientState)

local ANNOUNCE_SECONDS = 6
local ROLE_INTRO_SECONDS = 8

local HudController = {}

local phaseLabel: TextLabel
local timerLabel: TextLabel
local roleLabel: TextLabel
local announcement: TextLabel
local subAnnouncement: TextLabel

local phase: { [string]: any } = { Phase = "Waiting" }
local roleText = "" -- "Your role: ..." (shown again after a revive)
local announceToken = 0
local lastMoonSecond = -1

local function label(parent: Instance, name: string): TextLabel
	return parent:WaitForChild(name) :: TextLabel
end

local function formatTime(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function remaining(): number
	local endsAt = phase.EndsAt
	if type(endsAt) ~= "number" then
		return 0
	end
	return endsAt - workspace:GetServerTimeNow()
end

-- Shows a line of text in the middle of the screen for a few seconds.
local function showAnnouncement(text: string, color: Color3, subText: string?, seconds: number?)
	announceToken += 1
	local token = announceToken
	announcement.Text = text
	announcement.TextColor3 = color
	announcement.Visible = true
	subAnnouncement.Text = subText or ""
	subAnnouncement.Visible = subText ~= nil
	if seconds then
		task.delay(seconds, function()
			if announceToken == token then
				announcement.Visible = false
				subAnnouncement.Visible = false
			end
		end)
	end
end

local function phaseTitle(): string
	local name = phase.Phase
	if name == "Waiting" then
		return Loc.format("Phase.Waiting", { count = phase.Count, needed = phase.Needed })
	elseif name == "Day" then
		return Loc.format("Phase.Day", { day = phase.Day })
	elseif name == "Night" then
		return Loc.format("Phase.Night", { night = phase.Night })
	end
	return Loc.format("Phase." .. tostring(name))
end

local function onPhaseChanged(newPhase: any)
	if type(newPhase) ~= "table" then
		return
	end
	phase = newPhase
	phaseLabel.Text = phaseTitle()
	timerLabel.Visible = phase.Phase ~= "Waiting" and phase.Phase ~= "GameOver"
end

local function onRoleAssigned(roleId: any)
	if type(roleId) ~= "string" then
		return
	end
	local name = Loc.format("Role." .. roleId .. ".Name")
	roleText = Loc.format("Hud.YourRole", { role = name })
	roleLabel.Text = roleText
	roleLabel.Visible = true
	showAnnouncement(name, Color3.new(1, 1, 1), Loc.format("Role." .. roleId .. ".Desc"), ROLE_INTRO_SECONDS)
end

local function onAnnouncement(data: any)
	if type(data) ~= "table" or type(data.Key) ~= "string" then
		return
	end
	local color = if data.Style == "Red" then Config.Chat.AnnouncementColor else Color3.new(1, 1, 1)
	showAnnouncement(Loc.format(data.Key, data.Args), color, nil, ANNOUNCE_SECONDS)
end

local function onGameOver(data: any)
	if type(data) ~= "table" or type(data.EndingKey) ~= "string" then
		return
	end
	showAnnouncement(Loc.format(data.EndingKey), Color3.new(1, 1, 1), Loc.format("Faction." .. tostring(data.Winner)), nil)
end

local function onHeartbeat()
	timerLabel.Text = formatTime(remaining())
	-- "Full moon in N seconds" counts down live (GDD §6.3).
	if phase.Phase == "FullMoonWarning" then
		local seconds = math.max(0, math.ceil(remaining()))
		if seconds ~= lastMoonSecond then
			lastMoonSecond = seconds
			showAnnouncement(Loc.format("Phase.FullMoon", { seconds = seconds }), Config.Chat.AnnouncementColor, nil, 1.5)
		end
	else
		lastMoonSecond = -1
	end
end

function HudController.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("Hud")
	local topBar = hud:WaitForChild("TopBar")
	phaseLabel = label(topBar, "PhaseLabel")
	timerLabel = label(topBar, "TimerLabel")
	roleLabel = label(hud, "RoleLabel")
	announcement = label(hud, "Announcement")
	subAnnouncement = label(hud, "SubAnnouncement")
	-- Dead: say so, once, and keep it on the role line. Revived by the
	-- Doctor: the role line comes back.
	ClientState.Changed:Connect(function(key: string)
		if key ~= "Alive" then
			return
		end
		if not ClientState.Alive then
			roleLabel.Text = Loc.format("Hud.Dead")
			roleLabel.Visible = true
			showAnnouncement(Loc.format("Hud.Dead"), Color3.fromRGB(180, 180, 180), Loc.format("Hud.Ghost"), ROLE_INTRO_SECONDS)
		elseif roleText ~= "" then
			roleLabel.Text = roleText
		end
	end)

	Remotes.get("PhaseChanged").OnClientEvent:Connect(onPhaseChanged)
	Remotes.get("RoleAssigned").OnClientEvent:Connect(onRoleAssigned)
	Remotes.get("Announcement").OnClientEvent:Connect(onAnnouncement)
	Remotes.get("GameOver").OnClientEvent:Connect(onGameOver)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return HudController
