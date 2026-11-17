--!strict
--[[
	Client bootstrap for the Lobby place: the only LocalScript.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage.Shared.Audio)

local Controllers = script.Parent:WaitForChild("Controllers")

type Controller = { Start: () -> () }

for _, name in { "PadController", "MenuController", "TitleController" } do
	task.spawn(function()
		local controller = (require :: any)(Controllers:WaitForChild(name)) :: Controller
		xpcall(controller.Start, function(err)
			warn(`[Main] {name} failed to start: {err}`)
		end)
	end)
end

-- Every button in the lobby clicks (silent until the sound ID is set).
task.spawn(function()
	Audio.hookButtons(Players.LocalPlayer:WaitForChild("PlayerGui"))
end)
