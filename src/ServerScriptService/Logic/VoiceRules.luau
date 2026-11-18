--!strict
--[[
	VoiceRules — who may hear whom on voice chat (owner, 18 Nov 2026).
	  - Ghosts (the dead) are heard by ghosts only.
	  - The werewolf / pup in beast form cannot use voice at all.
	  - Everyone else is heard as usual (by whoever is close, Roblox's default).
	  - Before the match starts and after it ends, everyone can talk.
	Returned as an access rule for the speaker's microphone (AudioDeviceInput):
	  Open = true                -> anyone may hear
	  Open = false, Allow = {..} -> only these user ids may hear (empty = nobody)
]]

export type Speaker = {
	Id: number,
	Phase: "Lobby" | "Match" | "Over",
	Alive: boolean,
	Beast: boolean, -- in werewolf / pup form right now
}

export type Rule = { Open: boolean, Allow: { number } }

local VoiceRules = {}

function VoiceRules.forSpeaker(speaker: Speaker, everyone: { Speaker }): Rule
	if speaker.Phase ~= "Match" then
		return { Open = true, Allow = {} }
	end
	if not speaker.Alive then
		local ghosts: { number } = {}
		for _, other in everyone do
			if other.Id ~= speaker.Id and not other.Alive and other.Id > 0 then
				table.insert(ghosts, other.Id)
			end
		end
		table.sort(ghosts)
		return { Open = false, Allow = ghosts }
	end
	if speaker.Beast then
		return { Open = false, Allow = {} }
	end
	return { Open = true, Allow = {} }
end

return VoiceRules
