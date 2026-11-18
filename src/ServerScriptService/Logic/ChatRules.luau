--!strict
--[[
	ChatRules — pure chat routing (GDD §6.2, §12).

	Channels: General, Ghost.
	  Living players       speak in General.
	  [owner] 18 Nov 2026: the ghost chat and the wolf chat are one channel
	  ("Ghost"): the wolf side and the ghosts all read and type in it.
	  Ghosts (the dead)    may also type in General, but whatever a ghost
	                       writes reaches only other ghosts and the wolf side
	                       (shown in gray).
	Before roles are dealt and after the game is over, everyone simply talks
	in General.
]]

export type Phase = "Lobby" | "Match" | "Over"

export type Viewer = {
	Phase: Phase,
	Alive: boolean,
	WolfSide: boolean,
}

-- "Send" = in the channel and may type; "Read" = in the channel, read only.
export type Access = "Send" | "Read"

local ChatRules = {}

ChatRules.Channels = { "General", "Ghost" }

function ChatRules.membership(viewer: Viewer): { [string]: Access }
	if viewer.Phase ~= "Match" then
		return { General = "Send" }
	end
	if not viewer.Alive or viewer.WolfSide then
		return { General = "Send", Ghost = "Send" }
	end
	return { General = "Send" }
end

-- Does a message from `speaker` in `channel` reach `target`?
function ChatRules.canDeliver(channel: string, speaker: Viewer, target: Viewer): boolean
	if speaker.Phase ~= "Match" or target.Phase ~= "Match" then
		return true
	end
	-- A ghost's words only reach ghosts and the wolf side, whatever the channel.
	if not speaker.Alive then
		return not target.Alive or target.WolfSide
	end
	-- Living speakers: channel membership already limits who is listening.
	local access = ChatRules.membership(target)[channel]
	return access ~= nil
end

return ChatRules
