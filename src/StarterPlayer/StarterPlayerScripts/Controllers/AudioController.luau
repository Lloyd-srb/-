--!strict
--[[
	AudioController — the Match place's sounds (GDD §6.5).
	  - Sounds the server sends (only to players close enough to hear them).
	  - Ambience by phase: night music, crickets and an owl now and then at
	    night; day ambience by day; a rooster on mornings after a night; a
	    sting when the full-moon warning starts.
	  - Sounds for things this client already sees: shots and thrown axes
	    (public), the Killer's slash, a blocked attack, a blessing, a task
	    done, an item picked up, someone stunned.
	  - A jingle at the end: won or lost. A click for every button.
	Silent until the owner sends sound IDs (Config.Sounds = 0).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage.Shared.Audio)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AudioController = {}

local nightToken = 0
local random = Random.new()

local function setNight(night: boolean)
	Audio.loop("NightMusic", night)
	Audio.loop("Crickets", night)
	Audio.loop("DayAmbience", not night)
	nightToken += 1
	if night then
		local token = nightToken
		task.spawn(function()
			local range = Config.Audio.OwlEvery
			while nightToken == token do
				task.wait(random:NextNumber(range[1], range[2]))
				if nightToken == token then
					Audio.play("Owl")
				end
			end
		end)
	end
end

local function onPhase(phase: any)
	if type(phase) ~= "table" then
		return
	end
	local name = phase.Phase
	if name == "Night" then
		setNight(true)
	elseif name == "FullMoonWarning" then
		Audio.play("FullMoonSting")
	elseif name == "Day" or name == "MeetingCountdown" or name == "Meeting" then
		setNight(false)
		if name == "Day" and type(phase.Day) == "number" and phase.Day > 1 then
			Audio.play("MorningRooster")
		end
	elseif name == "GameOver" then
		Audio.loop("NightMusic", false)
		Audio.loop("Crickets", false)
		nightToken += 1
	end
end

local EFFECT_SOUNDS: { [string]: string } = {
	Blocked = "BlessingBreak",
	Blessed = "Blessing",
	TaskComplete = "TaskComplete",
	Gained = "ItemPickup",
}

local function onEffect(data: any)
	if type(data) ~= "table" then
		return
	end
	if data.Kind == "Shot" and typeof(data.From) == "Vector3" then
		Audio.play("Gunshot", data.From)
	elseif data.Kind == "Throw" and typeof(data.From) == "Vector3" then
		Audio.play("AxeThrow", data.From)
	elseif data.Kind == "Slash" and typeof(data.At) == "Vector3" then
		Audio.play("KnifeStab", data.At)
	elseif type(data.Kind) == "string" and EFFECT_SOUNDS[data.Kind] then
		Audio.play(EFFECT_SOUNDS[data.Kind])
	end
end

-- Stars appear over a stunned body (public): play the hit there.
local function watchStuns(body: Instance)
	body:GetAttributeChangedSignal("Stunned"):Connect(function()
		local root = body:FindFirstChild("HumanoidRootPart")
		if body:GetAttribute("Stunned") == true and root and root:IsA("BasePart") then
			Audio.play("StunHit", root.Position)
		end
	end)
end

function AudioController.Start()
	Remotes.get("Sound").OnClientEvent:Connect(function(data: any)
		if type(data) == "table" and type(data.Key) == "string" then
			Audio.play(data.Key, if typeof(data.At) == "Vector3" then data.At else nil)
		end
	end)
	Remotes.get("PhaseChanged").OnClientEvent:Connect(onPhase)
	Remotes.get("Effect").OnClientEvent:Connect(onEffect)
	Remotes.get("Scoreboard").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" or type(data.Rows) ~= "table" then
			return
		end
		for _, row in data.Rows do
			if type(row) == "table" and row.Id == Players.LocalPlayer.UserId then
				Audio.play(if row.Won then "WinJingle" else "LoseJingle")
			end
		end
	end)
	CollectionService:GetInstanceAddedSignal("MemberBody"):Connect(watchStuns)
	for _, body in CollectionService:GetTagged("MemberBody") do
		watchStuns(body)
	end
	Audio.hookButtons(Players.LocalPlayer:WaitForChild("PlayerGui"))
end

return AudioController
