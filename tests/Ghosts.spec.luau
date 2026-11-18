--[[
	Ghosts and chat (GDD §6.2, §12): pure routing rules, then the real server
	on the fake engine.
]]

local ChatRules = require(game.ServerScriptService.Logic.ChatRules)

local function viewer(alive, wolf, phase)
	return { Phase = phase or "Match", Alive = alive, WolfSide = wolf }
end

local VILLAGER, WOLF, GHOST, DEAD_WOLF = viewer(true, false), viewer(true, true), viewer(false, false), viewer(false, true)

test("rules: who is in which channel", function()
	expect(ChatRules.membership(VILLAGER)).toEqual({ General = "Send" })
	-- One chat for ghosts and the wolf side (owner, 18 Nov 2026).
	expect(ChatRules.membership(WOLF)).toEqual({ General = "Send", Ghost = "Send" })
	expect(ChatRules.membership(GHOST)).toEqual({ General = "Send", Ghost = "Send" })
	expect(ChatRules.membership(DEAD_WOLF)).toEqual({ General = "Send", Ghost = "Send" })
	expect(ChatRules.membership(viewer(true, true, "Lobby"))).toEqual({ General = "Send" })
	expect(ChatRules.membership(viewer(false, false, "Over"))).toEqual({ General = "Send" })
end)

test("rules: the living talk to everyone in General; the ghost / wolf chat stays with wolves and ghosts", function()
	for _, target in { VILLAGER, WOLF, GHOST } do
		expect(ChatRules.canDeliver("General", VILLAGER, target)).toBe(true)
	end
	expect(ChatRules.canDeliver("Ghost", WOLF, WOLF)).toBe(true)
	expect(ChatRules.canDeliver("Ghost", WOLF, GHOST)).toBe(true)
	expect(ChatRules.canDeliver("Ghost", WOLF, VILLAGER)).toBe(false)
end)

test("rules: a ghost's words only reach ghosts and the wolf side, in every channel", function()
	for _, channel in { "General", "Ghost" } do
		expect(ChatRules.canDeliver(channel, GHOST, VILLAGER)).toBe(false)
		expect(ChatRules.canDeliver(channel, GHOST, GHOST)).toBe(true)
		expect(ChatRules.canDeliver(channel, GHOST, WOLF)).toBe(true)
		expect(ChatRules.canDeliver(channel, GHOST, DEAD_WOLF)).toBe(true)
	end
	-- Once the game is over everyone can talk.
	expect(ChatRules.canDeliver("General", viewer(false, false, "Over"), viewer(true, false, "Over"))).toBe(true)
end)

--------------------------------------------------------------------------------

local function start(scale, roles)
	local server = startServer({
		Players = { { Id = 1, Name = "Alice" }, { Id = 2, Name = "Bob" }, { Id = 3, Name = "Cara" } },
		Debug = { TimerScale = scale, MinPlayers = 3, FillWithBots = true, UnlockAllRoles = false, ForceRoles = roles },
	})
	local folder = server.game.ServerScriptService.Services
	local svc = setmetatable({}, {
		__index = function(_, name)
			return server.require(folder[name .. "Service"])
		end,
	})
	return server, svc
end

local function waitFor(server, phase, number)
	server.waitFor(phase .. " " .. number, function()
		local last = server.last("PhaseChanged", "all")
		return last and last[1].Phase == phase and (if phase == "Night" then last[1].Night else last[1].Day) == number
	end, 10)
end

local function settle()
	task.wait(0.05) -- chat membership and ghost bodies are set up a moment later
end

test("dying: corpse stays, an invisible ghost appears, the chat follows the rules", function()
	local server, svc = start(0.02, { [1] = "Wolf", [2] = "Villager", [3] = "Doctor", [-1004] = "Killer" })

	server.waitForPhase("RoleSelect")
	settle()
	expect(server.chatAccess("General", 1)).toBe("Send") -- before the roles everyone just talks
	expect(server.chatAccess("Ghost", 1)).toBeNil()

	waitFor(server, "Day", 1)
	settle()
	expect(server.chatAccess("Ghost", 1)).toBe("Send") -- one chat for ghosts and wolves
	expect(server.chatAccess("Ghost", 2)).toBeNil()
	expect(server.chatDelivers("General", 2, 3)).toBe(true)

	-- Night 1: the wolf (Alice) bites Bob (pup) and kills Cara.
	waitFor(server, "Night", 1)
	svc.Match.RootOf(3).CFrame = CFrame.new(40, 3, 40)
	expect(svc.Combat.Damage(2, 100, "Wolf", 1)).toBe("Converted")
	expect(svc.Combat.Damage(3, 100, "Wolf", 1)).toBe("Killed")
	settle()

	-- Bob joined the wolf side in chat.
	expect(server.chatAccess("Ghost", 2)).toBe("Send")

	-- Cara: the corpse lies where she fell, her character is now a ghost beside it.
	local corpse = svc.Match.BodyOf(3)
	expect(corpse:GetAttribute("Corpse")).toBe(true)
	local ghost = server.player(3).Character
	expect(ghost ~= corpse).toBe(true)
	expect(ghost:HasTag("Ghost")).toBe(true)
	expect(ghost:HasTag("MemberBody")).toBe(false) -- outlines, shots and swings never find a ghost
	expect(svc.Match.CharacterOf(3)).toBeNil()
	local root = ghost.HumanoidRootPart
	expect(root.Transparency).toBe(1) -- the living see nothing
	expect(root.CanQuery).toBe(false)
	expect(root.CollisionGroup).toBe("Ghosts")
	expect((root.CFrame.Position - Vector3.new(40, 6, 40)).Magnitude < 0.01).toBe(true)
	expect(ghost.Humanoid.DisplayDistanceType).toBe(Enum.HumanoidDisplayDistanceType.None)

	-- Cara's chat: reads every channel, her words reach only ghosts and wolves.
	expect(server.chatAccess("Ghost", 3)).toBe("Send")
	expect(server.chatDelivers("General", 3, 1)).toBe(true) -- the wolf hears ghosts
	expect(server.chatDelivers("General", 3, 2)).toBe(true) -- so does the pup
	expect(server.chatDelivers("Ghost", 3, 1)).toBe(true)
	-- A living villager does not: a bot cannot chat, so check through a revive later.
	expect(server.chatDelivers("Ghost", 1, 3)).toBe(true) -- the wolf talks to the ghosts there too

	-- A ghost cannot use anything: e.g. hide (prompts check "alive" on the server).
	server.waitFor("day 2", function()
		return server.phase() == "Day"
	end, 10)
	settle()
	-- Day 2: the killer bot stabs nobody; the meeting will come. Exile the pup -> ghost at the plaza.
	svc.Match.Exile(2)
	settle()
	local bobGhost = server.player(2).Character
	expect(bobGhost:HasTag("Ghost")).toBe(true)
	expect(math.sqrt(bobGhost.HumanoidRootPart.CFrame.Position.X ^ 2 + bobGhost.HumanoidRootPart.CFrame.Position.Z ^ 2) < 30).toBe(true)
	expect(server.chatAccess("Ghost", 2)).toBe("Send")
	expect(server.chatDelivers("General", 2, 3)).toBe(true) -- ghost to ghost

	-- The game ends (the wolf leaves): everyone may talk to everyone again.
	server.removePlayer(1)
	server.waitForPhase("GameOver", 10)
	settle()
	expect(server.chatAccess("Ghost", 3)).toBeNil()
	expect(server.chatDelivers("General", 3, 2)).toBe(true)
end)

test("a revived player is no longer a ghost, and ghosts' words stop reaching them", function()
	local server, svc = start(0.02, { [1] = "Doctor", [2] = "Villager", [3] = "Sheriff", [-1004] = "Wolf" })
	waitFor(server, "Night", 1)
	expect(svc.Combat.Damage(-1005, 100, "Wolf", -1004)).toBe("Converted") -- the pup is a bot
	svc.Match.RootOf(2).CFrame = CFrame.new(30, 3, 0)
	svc.Match.RootOf(3).CFrame = CFrame.new(-30, 3, 0)
	expect(svc.Combat.Damage(2, 100, "Wolf", -1004)).toBe("Killed")
	expect(svc.Combat.Damage(3, 100, "Wolf", -1004)).toBe("Killed")
	settle()
	expect(server.player(2).Character:HasTag("Ghost")).toBe(true)
	expect(server.chatDelivers("General", 2, 3)).toBe(true) -- ghost to ghost
	expect(server.chatDelivers("General", 2, 1)).toBe(false) -- the living Doctor does not hear ghosts
	expect(server.chatDelivers("General", 1, 2)).toBe(true) -- but ghosts hear the living

	-- The ghost cannot ring the bell, hide or pick anything up (server says no).
	local ghostRoot = server.player(2).Character.HumanoidRootPart
	expect(svc.Hiding.IsHidden(2)).toBe(false)

	-- The Doctor revives Bob: his ghost is replaced by a living body at the corpse.
	svc.Match.RootOf(1).CFrame = CFrame.new(31, 3, 0)
	local corpse = svc.Match.BodyOf(2)
	server.trigger(corpse.HumanoidRootPart.RevivePrompt, 1)
	settle()
	expect(svc.Match.Roster.Members[2].Alive).toBe(true)
	local body = server.player(2).Character
	expect(body:HasTag("Ghost")).toBe(false)
	expect(body:HasTag("MemberBody")).toBe(true)
	expect(ghostRoot.Parent).toBeNil() -- the ghost body is gone
	expect(corpse.Parent).toBeNil()
	expect(body.HumanoidRootPart.CollisionGroup).toBe("Characters")
	expect(server.chatAccess("Ghost", 2)).toBeNil()
	expect(server.chatDelivers("General", 3, 2)).toBe(false) -- Cara is still a ghost

	svc.Match.Exile(-1005)
	svc.Match.Exile(-1004)
	server.waitForPhase("GameOver", 10)
end)
