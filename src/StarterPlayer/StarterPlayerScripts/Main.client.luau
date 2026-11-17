--!strict
--[[
	Client bootstrap: the only LocalScript. Starts every controller, then asks
	the server for the current state (covers events fired before we listened).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StarterGui = game:GetService("StarterGui")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Controllers = script.Parent:WaitForChild("Controllers")

type Controller = { Start: () -> () }

local names = {
	"HudController",
	"RoleSelectController",
	"VoteController",
	"WindowController",
	"PromptController",
	"WolfController",
	"RoleController",
	"EffectController",
	"TaskController",
	"ItemController",
	"GhostController",
	"ChatController",
	"HighlightController",
	"ShellAnimator",
	"HideController",
}

-- Each controller starts in its own thread: one waiting for missing UI must
-- not stop the others.
for _, name in names do
	task.spawn(function()
		local controller = (require :: any)(Controllers:WaitForChild(name)) :: Controller
		xpcall(controller.Start, function(err)
			warn(`[Main] {name} failed to start: {err}`)
		end)
	end)
end

-- No reset button: deaths are decided by the game. SetCore can fail while
-- the core scripts are still loading, so retry for a few seconds.
task.spawn(function()
	for _ = 1, 20 do
		if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", false) then
			return
		end
		task.wait(0.5)
	end
end)

Remotes.get("RequestSync"):FireServer()
