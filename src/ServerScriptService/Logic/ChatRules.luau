--!strict
--[[
	ChatRules — pure chat routing (GDD §6.2, §12).

	Channels: General, Wolf, Ghost.
	  Living players       speak in General.
	  The wolf side        also speaks in Wolf, and reads Ghost.
	  Ghosts (the dead)    read every channel and may type in General, Wolf
	                       and Ghost, but whatever a ghost writes reaches only
	                       other ghosts and the wolf side (shown in gray).
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

ChatRules.Channels = { "General", "Wolf", "Ghost" }

function ChatRules.membership(viewer: Viewer): { [string]: Access }
	if viewer.Phase ~= "Match" then
		return { General = "Send" }
	end
	if not viewer.Alive then
		return { General = "Send", Wolf = "Send", Ghost = "Send" }
	end
	if viewer.WolfSide then
		return { General = "Send", Wolf = "Send", Ghost = "Read" }
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
