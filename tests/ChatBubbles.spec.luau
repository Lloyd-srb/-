--[[
	Chat bubbles over heads, and the chat a player types into by default
	(owner, 24 Nov 2026): the ghost / wolf chat is a separate chat that never
	shows over anyone's head.
]]

local ChatBubbles = require(game.ReplicatedStorage.Shared.Logic.ChatBubbles)

local function person(alive, form, vanished)
	return { Alive = alive, Form = form, Vanished = vanished == true }
end

test("only General shows a bubble, over a visible living person", function()
	expect(ChatBubbles.shows("General", person(true, nil))).toBe(true)
	expect(ChatBubbles.shows("General", person(true, "Human"))).toBe(true)
	-- The ghost / wolf chat: never over anyone's head (a wolf by day included).
	expect(ChatBubbles.shows("Ghost", person(true, "Human"))).toBe(false)
	expect(ChatBubbles.shows("Ghost", person(true, "Wolf"))).toBe(false)
	expect(ChatBubbles.shows("Ghost", person(false, nil))).toBe(false)
	-- A ghost writing anywhere: no bubble.
	expect(ChatBubbles.shows("General", person(false, nil))).toBe(false)
	-- A monster in beast form, even in General: no bubble.
	expect(ChatBubbles.shows("General", person(true, "Wolf"))).toBe(false)
	expect(ChatBubbles.shows("General", person(true, "Pup"))).toBe(false)
	expect(ChatBubbles.shows("General", person(true, "Lurker"))).toBe(false)
	-- Someone invisible (a Ninja in smoke): no bubble.
	expect(ChatBubbles.shows("General", person(true, nil, true))).toBe(false)
end)

test("ghosts and monsters type into the ghost / wolf chat; people into General", function()
	expect(ChatBubbles.defaultChannel(true, "Human")).toBe("General")
	expect(ChatBubbles.defaultChannel(true, nil)).toBe("General")
	expect(ChatBubbles.defaultChannel(false, "Human")).toBe("Ghost")
	expect(ChatBubbles.defaultChannel(true, "Wolf")).toBe("Ghost")
	expect(ChatBubbles.defaultChannel(true, "Pup")).toBe("Ghost")
	expect(ChatBubbles.defaultChannel(true, "Lurker")).toBe("Ghost")
	-- The names match the server's channels.
	local ChatRules = require(game.ServerScriptService.Logic.ChatRules)
	expect(table.find(ChatRules.Channels, ChatBubbles.General) ~= nil).toBe(true)
	expect(table.find(ChatRules.Channels, ChatBubbles.Secret) ~= nil).toBe(true)
end)
