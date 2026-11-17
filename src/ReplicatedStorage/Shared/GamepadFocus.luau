--!strict
--[[
	GamepadFocus — client helper for console players: when a screen they must
	use opens (role selection, voting, the Monk's list, the scoreboard, the
	lobby menus), the controller's selection jumps to its first button, so
	the D-pad / stick works at once. Mouse, keyboard and touch are untouched.
]]

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local GamepadFocus = {}

function GamepadFocus.usingGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.Gamepad1
		or last == Enum.UserInputType.Gamepad2
		or last == Enum.UserInputType.Gamepad3
		or last == Enum.UserInputType.Gamepad4
end

-- Selects `target` (or the first visible button inside it) for the gamepad.
function GamepadFocus.offer(target: Instance?)
	if not target or not GamepadFocus.usingGamepad() then
		return
	end
	local button: GuiObject? = nil
	if target:IsA("GuiButton") then
		button = target
	else
		for _, child in target:GetDescendants() do
			if child:IsA("GuiButton") and child.Visible then
				button = child
				break
			end
		end
	end
	if button then
		GuiService.SelectedObject = button
	end
end

-- Lets go of the selection when a screen closes.
function GamepadFocus.release(container: Instance)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(container) then
		GuiService.SelectedObject = nil
	end
end

return GamepadFocus
