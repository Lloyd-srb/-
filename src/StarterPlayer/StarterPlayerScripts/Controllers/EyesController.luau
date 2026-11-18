--!strict
--[[
	EyesController — "eyes closed" (owner, 18 Nov 2026): when the night falls
	and when the morning comes, the screen goes black for about 3 seconds
	while the server moves everyone home, then opens again. The server only
	sends this to the living who are not on the wolf side.
	The ScreenGui is built by build/BuildUI.luau (StarterGui.EyesUI).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EyesController = {}

local token = 0

function EyesController.Start()
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("EyesUI")
	local black = gui:WaitForChild("Black") :: Frame
	local cfg = Config.EyesClosed

	Remotes.get("EyesClosed").OnClientEvent:Connect(function(data: any)
		local seconds = if type(data) == "table" and type(data.Seconds) == "number" then data.Seconds else cfg.Seconds
		token += 1
		local mine = token
		black.Visible = true
		TweenService:Create(black, TweenInfo.new(cfg.FadeIn), { BackgroundTransparency = 0 }):Play()
		task.delay(math.max(0, seconds - cfg.FadeOut), function()
			if token ~= mine then
				return
			end
			local open = TweenService:Create(black, TweenInfo.new(cfg.FadeOut), { BackgroundTransparency = 1 })
			open.Completed:Connect(function()
				if token == mine then
					black.Visible = false
				end
			end)
			open:Play()
		end)
	end)
end

return EyesController
