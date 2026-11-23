--[[
	Writes the role icon designs (Shared.RoleIcons) to JSON for render.py.
	Usage (repo root):  lune run tools/roleicons/export.luau <out.json>
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Harness = require("../lib/Harness")

local loaded = Harness.load("src")
local Shared = loaded.game.ReplicatedStorage.Shared
local Config = loaded.require(Shared.Config)
local RoleIcons = loaded.require(Shared.RoleIcons)

local function color(c)
	return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) }
end

local order = { "Wolf", "Pup", "Lurker" }
for _, roleId in Config.RoleOrder do
	table.insert(order, roleId)
end

local out = { order = order, icons = {}, rings = {}, names = {} }
for _, roleId in order do
	local shapes = {}
	for _, shape in RoleIcons.Designs[roleId] do
		table.insert(shapes, {
			x = shape.X,
			y = shape.Y,
			w = shape.W,
			h = shape.H,
			r = shape.R or 0,
			rot = shape.Rot or 0,
			t = shape.T or 0,
			color = color(shape.Color),
			stroke = if shape.Stroke then { color = color(shape.Stroke.Color), width = shape.Stroke.Width } else nil,
		})
	end
	out.icons[roleId] = shapes
	out.rings[roleId] = color(RoleIcons.RingColors[RoleIcons.factionOf(roleId, Config.Roles)])
end
local Strings = loaded.require(Shared.Strings)
for _, roleId in order do
	local entry = Strings["Role." .. roleId .. ".Name"] or Strings["Monster." .. roleId .. ".Name"]
	out.names[roleId] = { en = entry.en, th = entry.th }
end

-- The how-to-play pages (pictures + English text) for the tutorial preview.
local Tutorial = loaded.require(Shared.Tutorial)
out.tutorial = {}
for _, page in Tutorial.Pages do
	table.insert(out.tutorial, {
		icons = page.Icons,
		title = Strings[page.Key .. ".Title"].en,
		body = Strings[page.Key .. ".Body"].en,
	})
end
out.buttons = { nextText = Strings["Tutorial.Next"].en, done = Strings["Tutorial.Done"].en }

local function shapesOf(design)
	local shapes = {}
	for _, shape in design do
		table.insert(shapes, {
			x = shape.X,
			y = shape.Y,
			w = shape.W,
			h = shape.H,
			r = shape.R or 0,
			rot = shape.Rot or 0,
			t = shape.T or 0,
			color = color(shape.Color),
			stroke = if shape.Stroke then { color = color(shape.Stroke.Color), width = shape.Stroke.Width } else nil,
		})
	end
	return shapes
end

-- The lobby's Monster window (first monster, every wolf skin).
local monster = Config.monsterDef(process.env.MONSTER or "Werewolf")
local skins = if monster.Id == "Werewolf"
	then { { name = Strings["Monster.PlainSkin"].en, shapes = shapesOf(RoleIcons.wolfDesign(nil)) } }
	else { { name = Strings["Monster.NoSkins"].en, shapes = shapesOf(RoleIcons.Designs[monster.Id]) } }
for _, skinId in if monster.Id == "Werewolf" then Config.SkinOrder else {} do
	local def = Config.Skins[skinId]
	if def.Slot == "Wolf" then
		table.insert(skins, { name = Strings["Skin." .. skinId .. ".Name"].en, shapes = shapesOf(RoleIcons.wolfDesign(def.Paint)) })
	end
end
local function text(key, args)
	local s = Strings[key].en
	for name, value in args or {} do
		s = s:gsub("{" .. name .. "[^}]*}", tostring(value))
	end
	return s
end
local sniff, sprint = Config.Wolf.Sniff, Config.Wolf.Sprint
out.monster = {
	name = text("Monster." .. monster.Id .. ".Name"),
	skins = skins,
	ring = color(RoleIcons.RingColors.Wolf),
	stats = {
		{ text("Monster.Stat.RunSpeed"), monster.Stats.RunSpeed },
		{ text("Monster.Stat.AttackPower"), monster.Stats.AttackPower },
		{ text("Monster.Stat.AttackSpeed"), monster.Stats.AttackSpeed },
		{ text("Monster.Stat.Vision"), monster.Stats.Vision },
	},
	boxes = if monster.Id == "Lurker"
		then {
			{ text("Monster.Passive"), text("Monster.Lurker.Passive", { bonus = Config.Lurker.WaterSpeedBonus, wade = Config.Map.Moat.WadeSpeed }) },
			{ text("Monster.Ability", { n = 1 }), text("Monster.Lurker.Ability1", { damage = Config.monsterStat("Lurker", "AttackPower"), range = Config.Lurker.Bullet.Range, cooldown = Config.monsterStat("Lurker", "AttackSpeed") }) },
			{ text("Monster.Ability", { n = 2 }), text("Monster.Lurker.Ability2", { cooldown = Config.Lurker.Vanish.Cooldown }) },
			{ text("Monster.Folklore"), text("Monster.Lurker.Folklore") },
		}
		else {
			{ text("Monster.Passive"), text("Monster." .. monster.Id .. ".Passive", { speed = Config.Wolf.WalkSpeed, human = Config.Human.WalkSpeed, cooldown = Config.Wolf.AttackCooldown }) },
			{ text("Monster.Ability", { n = 1 }), text("Monster." .. monster.Id .. ".Ability1", { duration = sniff.Duration, cooldown = sniff.Cooldown }) },
			{ text("Monster.Ability", { n = 2 }), text("Monster." .. monster.Id .. ".Ability2", { speed = sprint.Speed, duration = sprint.Duration, maul = sprint.MaulDuration, cooldown = sprint.Cooldown }) },
			{ text("Monster.Folklore"), text("Monster." .. monster.Id .. ".Folklore") },
		},
	carousel = (function()
		local list = {}
		for _, m in Config.Monsters do
			table.insert(list, shapesOf(if m.Id == "Werewolf" then RoleIcons.wolfDesign(nil) else RoleIcons.Designs[m.Id]))
		end
		return list
	end)(),
	current = (function()
		for index, m in Config.Monsters do
			if m.Id == monster.Id then
				return index
			end
		end
		return 1
	end)(),
	locked = Config.MonsterLockedSlots,
	labels = { skins = text("Monster.Skins"), stats = text("Monster.Stats"), select = text("Monster.Selected") },
}

fs.writeFile(process.args[1] or "role_icons.json", serde.encode("json", out))
