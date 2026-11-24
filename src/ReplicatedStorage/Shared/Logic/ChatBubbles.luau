--!strict
--[[
	ChatBubbles — which chat messages show as a bubble over the speaker's head,
	and which chat a player types into by default (owner, 24 Nov 2026).

	Roblox's own chat bubbles are switched off (build/BuildSettings.luau and
	ChatController); ChatController draws the game's bubbles, only when this
	module says so:
	  - Only messages in the General chat. The ghost / wolf chat ("Ghost") is
	    a separate, secret chat: never over anyone's head.
	  - Never over a ghost.
	  - Never over a monster in beast form: it cannot talk, and a bubble would
	    tell everyone who the monster is.
	  - [ASSUMED] Never over someone invisible (a Ninja in smoke, The Lurker).

	Typing: ghosts, and monsters in beast form, type into the ghost / wolf
	chat. A person (the wolf side too, by day) types into General and can
	switch to the other tab.
]]

export type Speaker = {
	Alive: boolean,
	Form: string?, -- nil or "Human" = a person; "Wolf" / "Pup" / "Lurker" = beast form
	Vanished: boolean,
}

local ChatBubbles = {}

ChatBubbles.General = "General"
ChatBubbles.Secret = "Ghost" -- the ghost / wolf chat (one channel, owner 18 Nov 2026)

local function isBeast(form: string?): boolean
	return form ~= nil and form ~= "Human"
end

-- Does a message typed by `speaker` in `channel` show over their head?
function ChatBubbles.shows(channel: string, speaker: Speaker): boolean
	if channel ~= ChatBubbles.General then
		return false -- the ghost / wolf chat stays off everyone's head
	end
	if not speaker.Alive or isBeast(speaker.Form) or speaker.Vanished then
		return false
	end
	return true
end

-- The chat the input bar points at by default.
function ChatBubbles.defaultChannel(alive: boolean, form: string?): string
	if not alive or isBeast(form) then
		return ChatBubbles.Secret
	end
	return ChatBubbles.General
end

return ChatBubbles
