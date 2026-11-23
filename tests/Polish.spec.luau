--[[
	Milestone 10 polish checks: language (every text translated, nothing typed
	straight into the UI), controls (console / touch), and performance budgets
	(how much the map costs, nothing loose to simulate).
]]

local Strings = require(game.ReplicatedStorage.Shared.Strings)
local lobby = loadLobby()

--------------------------------------------------------------------------------
-- Language
--------------------------------------------------------------------------------

-- Texts whose Thai version is meant to have no Thai letters: names the GDD
-- itself writes in English in Thai (coin, Diamond, Pass, Premium, First aid,
-- Cross, MVP, EXP), "Ahem!", and pure numbers / symbols.
local LATIN_IN_THAI = {
	["Menu.Pass"] = true,
	["Menu.Price"] = true,
	["Monster.Price"] = true,
	["Wallet.Coins"] = true,
	["Wallet.Diamonds"] = true,
	["Buy.Coins"] = true,
	["Buy.Diamonds"] = true,
	["Buy.Robux"] = true,
	["Menu.Mastery"] = true,
	["Shop.CoinPack"] = true,
	["Pass.Row"] = true,
	["Reward.Coins"] = true,
	["Reward.Diamonds"] = true,
	["Reward.Premium"] = true,
	["Spin.Odds"] = true,
	["Vote.ChiefTieBreak"] = true,
	["End.Reward"] = true,
	["End.MvpBonus"] = true,
	["End.Mvp"] = true,
	["Item.FirstAid.Name"] = true,
	["Item.Cross.Name"] = true,
	["Tutorial.Page"] = true, -- "1 / 6"
	["Rarity.Rare"] = true, -- rarity names stay in English (owner, 18 Nov 2026)
	["Rarity.Epic"] = true,
	["Rarity.Legendary"] = true,
}

local function hasThai(text)
	local plain = text:gsub("{[^}]*}", "")
	for _, code in utf8.codes(plain) do
		if code >= 0x0E00 and code <= 0x0E7F then
			return true
		end
	end
	return false
end

test("language: every Thai text is really Thai (except names the GDD keeps in English)", function()
	local missing = {}
	for key, entry in Strings do
		if not hasThai(entry.th) and not LATIN_IN_THAI[key] then
			table.insert(missing, key)
		end
	end
	table.sort(missing)
	if #missing > 0 then
		error("not translated to Thai: " .. table.concat(missing, ", "))
	end
end)

test("language: the same {placeholders} in English and Thai", function()
	for key, entry in Strings do
		local function names(text)
			local list = {}
			for name in text:gmatch("{(%w+)") do
				table.insert(list, name)
			end
			table.sort(list)
			return table.concat(list, ",")
		end
		if names(entry.en) ~= names(entry.th) then
			error(`{key}: English uses {names(entry.en)}, Thai uses {names(entry.th)}`)
		end
	end
end)

test("language: no script types player-facing words straight into the UI", function()
	local checked = 0
	for _, place in { game, lobby.game } do
		for _, instance in place:GetDescendants() do
			if instance:IsA("LuaSourceContainer") and instance.Name ~= "Strings" and instance.Name ~= "Config" then
				checked += 1
				for _, pattern in {
					'%.Text = "([^"]*)"',
					'PlaceholderText = "([^"]*)"',
					'ToolTip = "([^"]*)"',
					'ObjectText = "([^"]*)"',
					'ActionText = "([^"]*)"',
					':SetTitle%([^,]+, "([^"]*)"',
					':Kick%("([^"]*)"',
				} do
					for text in instance.Source:gmatch(pattern) do
						if text:find("%a") then
							error(`{instance:GetFullName()} shows untranslated text "{text}"`)
						end
					end
				end
			end
		end
	end
	expect(checked > 50).toBe(true)
end)

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------

test("controls: gamepad X is left to the hold prompts; touch buttons use Roblox's layout", function()
	for _, place in { game, lobby.game } do
		for _, instance in place:GetDescendants() do
			if instance:IsA("LuaSourceContainer") and instance.Name:match("Controller$") then
				local source = instance.Source
				if source:find("ContextActionService") and source:find("Enum%.KeyCode%.ButtonX") then
					error(`{instance.Name} binds gamepad X (it would also trigger "hold" prompts)`)
				end
				if source:find("ContextActionService:SetPosition") then
					error(`{instance.Name} places touch buttons by hand (they can cover the jump button)`)
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- Performance
--------------------------------------------------------------------------------

local function partsUnder(root)
	local count, loose = 0, {}
	for _, instance in root:GetDescendants() do
		if instance:IsA("BasePart") then
			count += 1
			if not instance.Anchored then
				table.insert(loose, instance:GetFullName())
			end
		end
	end
	return count, loose
end

test("performance: the village fits the part budget and nothing in it is loose", function()
	runBuilder("build/BuildVillage.luau")
	local count, loose = partsUnder(workspace.Map)
	expect(count < 3000).toBe(true) -- [ASSUMED] budget for phones; about 1,400 today
	if #loose > 0 then
		error("unanchored map parts (physics every frame): " .. table.concat(loose, ", ", 1, math.min(#loose, 5)))
	end
	-- Decorations never take part in touches, rays or collisions.
	for _, instance in workspace.Map:GetDescendants() do
		if instance:IsA("BasePart") and instance.Name == "InteriorZone" then
			expect(instance.CanQuery or instance.CanTouch or instance.CanCollide).toBe(false)
		end
	end
end)

test("performance: the lobby fits the part budget and nothing in it is loose", function()
	runBuilderIn(lobby, "build/lobby/BuildLobby.luau")
	local count, loose = partsUnder(lobby.game.Workspace.Lobby)
	expect(count < 1000).toBe(true)
	expect(#loose).toBe(0)
end)
