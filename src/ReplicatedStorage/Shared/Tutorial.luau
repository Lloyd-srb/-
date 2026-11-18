--!strict
--[[
	Tutorial — the "how to play" pages in the lobby (owner, 17 Nov 2026):
	a picture (role icons), a title and a few lines per page, a "Next"
	button, and "Got it!" on the last page. Shown once to new players and
	again from the News page. Texts are in Strings ("Tutorial.<n>.Title" /
	"Tutorial.<n>.Body").
]]

export type Page = {
	Key: string, -- Strings prefix
	Icons: { string }, -- RoleIcons designs for the picture
}

local Tutorial = {}

Tutorial.Pages = {
	{ Key = "Tutorial.1", Icons = { "Villager", "Wolf", "Villager" } }, -- who is the werewolf?
	{ Key = "Tutorial.2", Icons = { "Chief", "Villager", "Sheriff" } }, -- the day, tasks, the meeting
	{ Key = "Tutorial.3", Icons = { "Wolf", "Pup" } }, -- the night
	{ Key = "Tutorial.4", Icons = { "Doctor", "Seer", "Bodyguard", "Priest", "Engineer" } }, -- roles
	{ Key = "Tutorial.5", Icons = { "Killer", "Fool", "FireManiac" } }, -- special roles (Killer, Fool, Fire Maniac): not on your side
	{ Key = "Tutorial.6", Icons = { "Villager", "Sheriff", "Doctor" } }, -- survive!
} :: { Page }

return Tutorial
