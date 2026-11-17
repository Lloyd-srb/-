--!strict
--[[
	Client bootstrap for the Lobby place: the only LocalScript.
]]

local Controllers = script.Parent:WaitForChild("Controllers")

type Controller = { Start: () -> () }

for _, name in { "PadController", "MenuController" } do
	task.spawn(function()
		local controller = (require :: any)(Controllers:WaitForChild(name)) :: Controller
		xpcall(controller.Start, function(err)
			warn(`[Main] {name} failed to start: {err}`)
		end)
	end)
end
