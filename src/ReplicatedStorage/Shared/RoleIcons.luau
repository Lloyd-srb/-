--!strict
--[[
	RoleIcons — round portrait icons for every role, the werewolf and the pup:
	a front-facing face with the role's look (hat, glasses, hood, ...).

	The icons are drawn with plain GUI shapes (rounded frames), so they need
	no uploaded images and work right away. Each design is a list of shapes on
	a 100 x 100 grid, back to front:
	  X, Y   centre      W, H   size        R   corner (0 = square, 0.5 = round)
	  Rot    degrees clockwise              T   transparency (0 = solid)
	  Stroke optional outline { Color, Width } (Width in grid units)
	The whole icon is clipped to a circle.

	tools/roleicons renders the same data to PNG previews (docs/role_icons.png).
]]

export type Shape = {
	X: number,
	Y: number,
	W: number,
	H: number,
	R: number?,
	Rot: number?,
	T: number?,
	Color: Color3,
	Stroke: { Color: Color3, Width: number }?,
}

local rgb = Color3.fromRGB

local Palette = {
	Skin = rgb(255, 214, 170),
	SkinShade = rgb(240, 190, 145),
	Ink = rgb(45, 40, 50),
	Cheek = rgb(255, 150, 150),
	White = rgb(255, 255, 255),
	Gold = rgb(255, 205, 60),
	GoldDark = rgb(215, 160, 30),
	WolfFur = rgb(112, 114, 122),
	WolfDark = rgb(76, 78, 88),
	WolfLight = rgb(170, 172, 182),
	WolfEye = rgb(255, 221, 51),
}

local RoleIcons = {}

-- Ring colour around each icon, by faction.
RoleIcons.RingColors = {
	Village = rgb(255, 255, 255),
	Wolf = rgb(255, 221, 51),
	Killer = rgb(230, 70, 80),
	Fool = rgb(255, 120, 200),
	FireManiac = rgb(255, 130, 40),
} :: { [string]: Color3 }

-- A plain round face: shoulders, head, eyes, cheeks, mouth.
local function face(shirt: Color3, opts: { [string]: any }?): { Shape }
	local o: { [string]: any } = opts or {}
	local shapes: { Shape } = {
		{ X = 50, Y = 100, W = 78, H = 40, R = 0.45, Color = shirt },
		{ X = 50, Y = 57, W = 52, H = 50, R = 0.42, Color = o.Skin or Palette.Skin },
	}
	if not o.NoEyes then
		local eyeH = o.EyeH or 8
		table.insert(shapes, { X = 40, Y = 57, W = o.EyeW or 6, H = eyeH, R = 0.5, Color = Palette.Ink })
		table.insert(shapes, { X = 60, Y = 57, W = o.EyeW or 6, H = eyeH, R = 0.5, Color = Palette.Ink })
	end
	if not o.NoCheeks then
		table.insert(shapes, { X = 34, Y = 66, W = 8, H = 5, R = 0.5, T = 0.35, Color = Palette.Cheek })
		table.insert(shapes, { X = 66, Y = 66, W = 8, H = 5, R = 0.5, T = 0.35, Color = Palette.Cheek })
	end
	if not o.NoMouth then
		table.insert(shapes, { X = 50, Y = 70, W = o.MouthW or 10, H = 3, R = 0.5, Color = Palette.Ink })
	end
	return shapes
end

local function background(color: Color3): Shape
	return { X = 50, Y = 50, W = 100, H = 100, R = 0.5, Color = color }
end

local function join(...: { Shape }): { Shape }
	local all: { Shape } = {}
	for _, list in { ... } do
		for _, shape in list do
			table.insert(all, shape)
		end
	end
	return all
end

local function wolfHead(
	fur: Color3,
	dark: Color3,
	light: Color3,
	scale: number,
	eyeSize: number,
	angry: boolean,
	eye: Color3?
): { Shape }
	local s = scale
	local function at(x: number, y: number): (number, number)
		return 50 + (x - 50) * s, 58 + (y - 58) * s
	end
	local shapes: { Shape } = {}
	local function add(x: number, y: number, w: number, h: number, r: number, rot: number, color: Color3, t: number?)
		local px, py = at(x, y)
		table.insert(shapes, { X = px, Y = py, W = w * s, H = h * s, R = r, Rot = rot, Color = color, T = t })
	end
	add(31, 33, 22, 22, 0.15, 45, dark) -- ears
	add(69, 33, 22, 22, 0.15, 45, dark)
	add(31, 35, 11, 11, 0.15, 45, rgb(230, 150, 160))
	add(69, 35, 11, 11, 0.15, 45, rgb(230, 150, 160))
	add(50, 60, 62, 52, 0.42, 0, fur) -- head
	add(36, 70, 16, 12, 0.5, 20, light) -- cheek fluff
	add(64, 70, 16, 12, 0.5, -20, light)
	add(50, 71, 28, 22, 0.45, 0, light) -- muzzle
	add(50, 64, 11, 7, 0.5, 0, Palette.Ink) -- nose
	add(50, 77, 12, 3, 0.5, 0, dark) -- mouth
	add(39, 54, eyeSize * 1.5, eyeSize, 0.5, 12, eye or Palette.WolfEye) -- glowing eyes
	add(61, 54, eyeSize * 1.5, eyeSize, 0.5, -12, eye or Palette.WolfEye)
	add(39, 54, 2.4, eyeSize * 0.8, 0.5, 0, Palette.Ink) -- slit pupils
	add(61, 54, 2.4, eyeSize * 0.8, 0.5, 0, Palette.Ink)
	if angry then -- brows slanting down to the nose
		add(39, 47, 14, 3.5, 0.5, 20, dark)
		add(61, 47, 14, 3.5, 0.5, -20, dark)
	end
	add(45, 81, 4, 5, 0.1, 45, Palette.White) -- fangs
	add(55, 81, 4, 5, 0.1, 45, Palette.White)
	return shapes
end

RoleIcons.Designs = {
	-- Straw hat farmer.
	Villager = join({ background(rgb(122, 190, 110)) }, face(rgb(150, 110, 70)), {
		{ X = 50, Y = 39, W = 80, H = 9, R = 0.5, Color = rgb(235, 205, 120) },
		{ X = 50, Y = 29, W = 42, H = 20, R = 0.35, Color = rgb(235, 205, 120) },
		{ X = 50, Y = 35, W = 42, H = 4, R = 0, Color = rgb(190, 80, 60) },
	}),

	-- Cowboy hat, moustache, gold badge.
	Sheriff = join({ background(rgb(80, 120, 200)) }, face(rgb(150, 105, 60), { MouthW = 8 }), {
		{ X = 50, Y = 66, W = 22, H = 5, R = 0.5, Color = rgb(120, 75, 40) },
		{ X = 50, Y = 38, W = 86, H = 9, R = 0.5, Color = rgb(130, 85, 45) },
		{ X = 50, Y = 27, W = 44, H = 22, R = 0.35, Color = rgb(130, 85, 45) },
		{ X = 50, Y = 34, W = 44, H = 4, R = 0, Color = rgb(80, 50, 25) },
		{ X = 36, Y = 90, W = 10, H = 10, R = 0.15, Rot = 45, Color = Palette.Gold, Stroke = { Color = Palette.GoldDark, Width = 1 } },
	}),

	-- Head mirror, face mask, red cross.
	Doctor = join({ background(rgb(110, 200, 210)) }, face(Palette.White, { NoMouth = true, NoCheeks = true }), {
		{ X = 50, Y = 42, W = 54, H = 4, R = 0.5, Color = rgb(150, 150, 160) },
		{ X = 50, Y = 40, W = 15, H = 15, R = 0.5, Color = rgb(225, 230, 240), Stroke = { Color = rgb(150, 150, 160), Width = 1.5 } },
		{ X = 50, Y = 69, W = 34, H = 14, R = 0.3, Color = rgb(170, 220, 240) },
		{ X = 50, Y = 92, W = 12, H = 4, R = 0, Color = rgb(225, 60, 60) },
		{ X = 50, Y = 92, W = 4, H = 12, R = 0, Color = rgb(225, 60, 60) },
	}),

	-- Hood, closed eyes, third eye.
	Seer = join({ background(rgb(120, 90, 190)) }, {
		{ X = 22, Y = 24, W = 3, H = 3, R = 0.5, Color = Palette.White },
		{ X = 80, Y = 30, W = 2.5, H = 2.5, R = 0.5, Color = Palette.White },
		{ X = 74, Y = 16, W = 2, H = 2, R = 0.5, Color = Palette.White },
		{ X = 50, Y = 56, W = 70, H = 76, R = 0.45, Color = rgb(70, 45, 120) },
	}, face(rgb(70, 45, 120), { EyeH = 2.5, EyeW = 9 }), {
		{ X = 50, Y = 44, W = 7, H = 7, R = 0.2, Rot = 45, Color = rgb(120, 240, 255), Stroke = { Color = Palette.White, Width = 1 } },
	}),

	-- Crown, white beard and moustache.
	Chief = join({ background(rgb(235, 160, 60)) }, face(rgb(170, 40, 50), { NoMouth = true }), {
		{ X = 50, Y = 75, W = 38, H = 18, R = 0.45, Color = rgb(240, 240, 240) },
		{ X = 50, Y = 66, W = 26, H = 6, R = 0.5, Color = rgb(240, 240, 240) },
		{ X = 36, Y = 26, W = 9, H = 9, R = 0.1, Rot = 45, Color = Palette.Gold },
		{ X = 50, Y = 23, W = 10, H = 10, R = 0.1, Rot = 45, Color = Palette.Gold },
		{ X = 64, Y = 26, W = 9, H = 9, R = 0.1, Rot = 45, Color = Palette.Gold },
		{ X = 50, Y = 33, W = 46, H = 10, R = 0.2, Color = Palette.Gold, Stroke = { Color = Palette.GoldDark, Width = 1 } },
		{ X = 50, Y = 33, W = 5, H = 5, R = 0.5, Color = rgb(220, 50, 60) },
	}),

	-- Buzz cut, sunglasses, earpiece, tie.
	Bodyguard = join({ background(rgb(70, 80, 105)) }, face(rgb(30, 30, 36), { NoEyes = true, MouthW = 12 }), {
		{ X = 50, Y = 36, W = 50, H = 12, R = 0.4, Color = rgb(40, 35, 35) },
		{ X = 40, Y = 56, W = 15, H = 9, R = 0.3, Color = rgb(20, 20, 24) },
		{ X = 60, Y = 56, W = 15, H = 9, R = 0.3, Color = rgb(20, 20, 24) },
		{ X = 50, Y = 55, W = 6, H = 2, R = 0, Color = rgb(20, 20, 24) },
		{ X = 25, Y = 60, W = 4, H = 9, R = 0.5, Color = rgb(20, 20, 24) },
		{ X = 50, Y = 89, W = 12, H = 10, R = 0.1, Rot = 45, Color = Palette.White },
		{ X = 50, Y = 94, W = 5, H = 14, R = 0.2, Color = rgb(200, 40, 50) },
	}),

	-- Priest: neat hair, calm closed eyes, black cassock with a white collar,
	-- a small gold cross, golden halo.
	Priest = join({ background(rgb(170, 140, 210)) }, {
		{ X = 50, Y = 53, W = 76, H = 76, R = 0.5, Color = Palette.Gold },
		{ X = 50, Y = 53, W = 68, H = 68, R = 0.5, Color = rgb(170, 140, 210) },
	}, face(rgb(32, 30, 38), { EyeH = 2.5, EyeW = 9 }), {
		{ X = 50, Y = 37, W = 52, H = 14, R = 0.45, Color = rgb(95, 65, 45) },
		{ X = 50, Y = 84, W = 10, H = 6, R = 0.2, Color = Palette.White },
		{ X = 50, Y = 94, W = 3, H = 11, R = 0, Color = Palette.Gold },
		{ X = 50, Y = 92, W = 9, H = 3, R = 0, Color = Palette.Gold },
	}),

	-- Yellow hard hat, goggles, safety vest.
	Engineer = join({ background(rgb(95, 135, 165)) }, face(rgb(255, 140, 30)), {
		{ X = 50, Y = 31, W = 52, H = 26, R = 0.5, Color = rgb(255, 205, 40) },
		{ X = 50, Y = 41, W = 64, H = 6, R = 0.5, Color = rgb(225, 170, 20) },
		{ X = 50, Y = 25, W = 6, H = 14, R = 0.5, Color = rgb(225, 170, 20) },
		{ X = 40, Y = 33, W = 10, H = 10, R = 0.5, Color = rgb(150, 220, 255), Stroke = { Color = rgb(60, 60, 70), Width = 1.5 } },
		{ X = 60, Y = 33, W = 10, H = 10, R = 0.5, Color = rgb(150, 220, 255), Stroke = { Color = rgb(60, 60, 70), Width = 1.5 } },
		{ X = 50, Y = 93, W = 78, H = 4, R = 0, Color = rgb(230, 235, 240) },
	}),

	-- Plague Doctor (owner, 18 Nov 2026): black beak mask, black wide hat,
	-- clear white glass eyes, dark coat, and the red potion.
	PlagueDoctor = join({ background(rgb(70, 110, 90)) }, face(rgb(35, 32, 40), {
		Skin = rgb(28, 26, 32),
		NoEyes = true,
		NoMouth = true,
		NoCheeks = true,
	}), {
		{ X = 50, Y = 72, W = 15, H = 26, R = 0.45, Color = rgb(18, 17, 22) },
		{ X = 50, Y = 84, W = 10, H = 10, R = 0.15, Rot = 45, Color = rgb(18, 17, 22) },
		{ X = 50, Y = 69, W = 2, H = 12, R = 0, Color = rgb(60, 58, 68) },
		{ X = 39, Y = 53, W = 14, H = 14, R = 0.5, T = 0.15, Color = rgb(235, 240, 245), Stroke = { Color = rgb(150, 150, 160), Width = 1.5 } },
		{ X = 61, Y = 53, W = 14, H = 14, R = 0.5, T = 0.15, Color = rgb(235, 240, 245), Stroke = { Color = rgb(150, 150, 160), Width = 1.5 } },
		{ X = 36, Y = 50, W = 4, H = 4, R = 0.5, Color = Palette.White },
		{ X = 58, Y = 50, W = 4, H = 4, R = 0.5, Color = Palette.White },
		{ X = 50, Y = 35, W = 84, H = 8, R = 0.5, Color = rgb(14, 13, 18) },
		{ X = 50, Y = 24, W = 40, H = 20, R = 0.2, Color = rgb(14, 13, 18) },
		{ X = 50, Y = 31, W = 40, H = 3, R = 0, Color = rgb(60, 58, 68) },
		{ X = 77, Y = 74, W = 6, H = 3, R = 0.2, Color = rgb(140, 95, 55) },
		{ X = 77, Y = 78, W = 5, H = 6, R = 0.1, Color = rgb(220, 220, 230) },
		{ X = 77, Y = 86, W = 14, H = 14, R = 0.5, Color = rgb(215, 30, 45), Stroke = { Color = Palette.White, Width = 1 } },
		{ X = 74, Y = 83, W = 3, H = 4, R = 0.5, T = 0.3, Color = Palette.White },
	}),

	-- Thief: knit beanie, black bandit mask, striped shirt, loot sack.
	Thief = join({ background(rgb(60, 62, 85)) }, face(rgb(40, 40, 52), { NoEyes = true, MouthW = 8 }), {
		{ X = 50, Y = 88, W = 78, H = 4, R = 0, T = 0.15, Color = rgb(235, 235, 240) },
		{ X = 50, Y = 97, W = 78, H = 4, R = 0, T = 0.15, Color = rgb(235, 235, 240) },
		{ X = 50, Y = 55, W = 56, H = 13, R = 0.4, Color = rgb(22, 22, 28) },
		{ X = 23, Y = 60, W = 9, H = 4, R = 0.5, Rot = -30, Color = rgb(22, 22, 28) },
		{ X = 40, Y = 55, W = 9, H = 6, R = 0.5, Color = Palette.Skin },
		{ X = 60, Y = 55, W = 9, H = 6, R = 0.5, Color = Palette.Skin },
		{ X = 41, Y = 55, W = 4, H = 4, R = 0.5, Color = Palette.Ink },
		{ X = 61, Y = 55, W = 4, H = 4, R = 0.5, Color = Palette.Ink },
		{ X = 50, Y = 34, W = 52, H = 22, R = 0.45, Color = rgb(70, 72, 90) },
		{ X = 50, Y = 42, W = 56, H = 7, R = 0.4, Color = rgb(50, 52, 68) },
		{ X = 50, Y = 22, W = 8, H = 8, R = 0.5, Color = rgb(50, 52, 68) },
		{ X = 81, Y = 86, W = 24, H = 22, R = 0.45, Color = rgb(175, 145, 95) },
		{ X = 81, Y = 74, W = 9, H = 5, R = 0.3, Color = rgb(135, 105, 65) },
		{ X = 81, Y = 87, W = 6, H = 6, R = 0.5, Color = Palette.Gold },
	}),

	-- Police: navy peaked cap with a gold badge, navy shirt, chest badge.
	Police = join({ background(rgb(70, 110, 185)) }, face(rgb(30, 45, 100)), {
		{ X = 50, Y = 31, W = 56, H = 20, R = 0.35, Color = rgb(28, 38, 85) },
		{ X = 50, Y = 38, W = 56, H = 4, R = 0, Color = rgb(15, 20, 50) },
		{ X = 50, Y = 42, W = 60, H = 6, R = 0.5, Color = rgb(15, 20, 50) },
		{ X = 50, Y = 30, W = 8, H = 8, R = 0.15, Rot = 45, Color = Palette.Gold, Stroke = { Color = Palette.GoldDark, Width = 1 } },
		{ X = 36, Y = 90, W = 8, H = 10, R = 0.3, Color = Palette.Gold, Stroke = { Color = Palette.GoldDark, Width = 1 } },
		{ X = 50, Y = 86, W = 6, H = 6, R = 0.1, Rot = 45, Color = rgb(20, 28, 70) },
	}),

	-- Detective: brown hat, trench coat collar, magnifying glass.
	Detective = join({ background(rgb(120, 98, 75)) }, face(rgb(195, 165, 115)), {
		{ X = 38, Y = 86, W = 14, H = 14, R = 0.1, Rot = 45, Color = rgb(165, 135, 88) },
		{ X = 62, Y = 86, W = 14, H = 14, R = 0.1, Rot = 45, Color = rgb(165, 135, 88) },
		{ X = 50, Y = 39, W = 76, H = 8, R = 0.5, Color = rgb(105, 75, 48) },
		{ X = 50, Y = 28, W = 46, H = 20, R = 0.35, Color = rgb(120, 88, 55) },
		{ X = 50, Y = 34, W = 46, H = 4, R = 0, Color = rgb(60, 40, 25) },
		{ X = 79, Y = 88, W = 5, H = 16, R = 0.3, Rot = -35, Color = rgb(110, 75, 40) },
		{ X = 71, Y = 75, W = 18, H = 18, R = 0.5, T = 0.35, Color = rgb(190, 230, 255), Stroke = { Color = rgb(90, 90, 100), Width = 2.5 } },
	}),

	-- Lover: pink, a big smile and a heart.
	Lover = join({ background(rgb(255, 165, 200)) }, face(rgb(230, 90, 130), { MouthW = 13 }), {
		{ X = 50, Y = 37, W = 52, H = 12, R = 0.45, Color = rgb(150, 85, 55) },
		{ X = 44, Y = 22, W = 14, H = 14, R = 0.5, Color = rgb(235, 45, 85) },
		{ X = 56, Y = 22, W = 14, H = 14, R = 0.5, Color = rgb(235, 45, 85) },
		{ X = 50, Y = 27, W = 13, H = 13, R = 0.1, Rot = 45, Color = rgb(235, 45, 85) },
		{ X = 34, Y = 66, W = 9, H = 6, R = 0.5, T = 0.1, Color = rgb(255, 120, 150) },
		{ X = 66, Y = 66, W = 9, H = 6, R = 0.5, T = 0.1, Color = rgb(255, 120, 150) },
	}),

	-- Fire Maniac: flames behind, wide eyes, a wild grin, a red oil can.
	FireManiac = join({
		background(rgb(95, 30, 22)),
		{ X = 28, Y = 32, W = 18, H = 18, R = 0.2, Rot = 45, Color = rgb(255, 120, 30) },
		{ X = 72, Y = 32, W = 18, H = 18, R = 0.2, Rot = 45, Color = rgb(255, 120, 30) },
		{ X = 50, Y = 22, W = 24, H = 24, R = 0.2, Rot = 45, Color = rgb(255, 90, 20) },
		{ X = 50, Y = 27, W = 12, H = 12, R = 0.2, Rot = 45, Color = rgb(255, 210, 60) },
	}, face(rgb(70, 60, 55), { NoEyes = true, NoMouth = true }), {
		{ X = 50, Y = 38, W = 50, H = 10, R = 0.4, Color = rgb(60, 35, 25) },
		{ X = 40, Y = 56, W = 11, H = 11, R = 0.5, Color = Palette.White, Stroke = { Color = Palette.Ink, Width = 1 } },
		{ X = 60, Y = 56, W = 11, H = 11, R = 0.5, Color = Palette.White, Stroke = { Color = Palette.Ink, Width = 1 } },
		{ X = 40, Y = 56, W = 3, H = 3, R = 0.5, Color = Palette.Ink },
		{ X = 60, Y = 56, W = 3, H = 3, R = 0.5, Color = Palette.Ink },
		{ X = 50, Y = 70, W = 18, H = 6, R = 0.5, Color = Palette.White, Stroke = { Color = Palette.Ink, Width = 1 } },
		{ X = 63, Y = 65, W = 7, H = 3, R = 0.5, T = 0.4, Color = rgb(60, 50, 50) },
		{ X = 86, Y = 76, W = 4, H = 9, R = 0.2, Rot = 30, Color = rgb(150, 150, 160) },
		{ X = 79, Y = 87, W = 14, H = 17, R = 0.15, Color = rgb(200, 55, 40), Stroke = { Color = rgb(120, 30, 20), Width = 1 } },
	}),

	-- Black hood, scarf over the mouth, red eyes, knife.
	Killer = join({ background(rgb(120, 30, 40)) }, {
		{ X = 50, Y = 56, W = 70, H = 78, R = 0.45, Color = rgb(25, 22, 28) },
	}, face(rgb(25, 22, 28), { NoEyes = true, NoMouth = true, NoCheeks = true, Skin = rgb(230, 220, 215) }), {
		{ X = 41, Y = 55, W = 10, H = 4, R = 0.5, Rot = 15, Color = rgb(230, 30, 40) },
		{ X = 59, Y = 55, W = 10, H = 4, R = 0.5, Rot = -15, Color = rgb(230, 30, 40) },
		{ X = 50, Y = 72, W = 56, H = 18, R = 0.3, Color = rgb(45, 40, 50) },
		{ X = 76, Y = 80, W = 7, H = 26, R = 0.3, Rot = 35, Color = rgb(215, 220, 230) },
		{ X = 69, Y = 91, W = 7, H = 10, R = 0.2, Rot = 35, Color = rgb(110, 70, 40) },
	}),

	-- Jester hat with bells, big grin, odd eyes.
	Fool = join({ background(rgb(220, 90, 160)) }, face(rgb(130, 60, 170), { NoEyes = true, NoMouth = true }), {
		{ X = 40, Y = 57, W = 9, H = 9, R = 0.5, Color = Palette.Ink },
		{ X = 60, Y = 58, W = 5, H = 5, R = 0.5, Color = Palette.Ink },
		{ X = 50, Y = 69, W = 24, H = 8, R = 0.5, Color = Palette.White, Stroke = { Color = Palette.Ink, Width = 1.5 } },
		{ X = 35, Y = 25, W = 14, H = 34, R = 0.5, Rot = -35, Color = rgb(140, 70, 190) },
		{ X = 65, Y = 25, W = 14, H = 34, R = 0.5, Rot = 35, Color = rgb(80, 190, 110) },
		{ X = 25, Y = 12, W = 9, H = 9, R = 0.5, Color = Palette.Gold },
		{ X = 75, Y = 12, W = 9, H = 9, R = 0.5, Color = Palette.Gold },
		{ X = 50, Y = 37, W = 54, H = 8, R = 0.4, Color = Palette.Gold },
	}),

	-- Grey werewolf under the full moon, glowing yellow eyes.
	Wolf = join({
		background(rgb(35, 45, 85)),
		{ X = 80, Y = 22, W = 24, H = 24, R = 0.5, Color = rgb(255, 245, 200) },
	}, wolfHead(Palette.WolfFur, Palette.WolfDark, Palette.WolfLight, 1, 8, true)),

	-- The pup: smaller, rounder, bigger eyes.
	Pup = join({
		background(rgb(90, 70, 130)),
		{ X = 78, Y = 24, W = 18, H = 18, R = 0.5, Color = rgb(255, 245, 200) },
	}, wolfHead(rgb(150, 152, 160), rgb(110, 112, 122), rgb(205, 207, 215), 0.86, 10, false)),
} :: { [string]: { Shape } }

--[[
	The werewolf portrait in a wolf skin's colours (Config.Skins[..].Paint keys
	Fur / FurDark / Eye; anything missing keeps the default grey wolf).
]]
function RoleIcons.wolfDesign(paint: { [string]: Color3 }?): { Shape }
	local p: { [string]: Color3 } = paint or {}
	local fur = p.Fur or Palette.WolfFur
	local dark = p.FurDark or Palette.WolfDark
	local light = p.Belly or fur:Lerp(Palette.White, 0.35)
	if not p.Fur then
		light = Palette.WolfLight
	end
	return join({
		background(rgb(35, 45, 85)),
		{ X = 80, Y = 22, W = 24, H = 24, R = 0.5, Color = rgb(255, 245, 200) },
	}, wolfHead(fur, dark, light, 1, 8, true, p.Eye))
end

-- Faction of each icon (for the ring colour).
function RoleIcons.factionOf(roleId: string, roles: { [string]: any }): string
	if roleId == "Pup" then
		return "Wolf"
	end
	local def = roles[roleId]
	return if def then def.Faction else "Village"
end

--[[
	Builds an icon as GUI: a round frame (the ring) holding a CanvasGroup that
	clips the drawing to a circle. `size` is in pixels. Returns the frame.
	`custom` draws that design instead (e.g. RoleIcons.wolfDesign(skinPaint)).
]]
function RoleIcons.create(roleId: string, size: number, ring: Color3?, custom: { Shape }?): Frame
	local design = custom or RoleIcons.Designs[roleId] or RoleIcons.Designs.Villager
	local holder = Instance.new("Frame")
	holder.Name = "RoleIcon"
	holder.Size = UDim2.fromOffset(size, size)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder:SetAttribute("RoleId", roleId)

	local canvas = Instance.new("CanvasGroup")
	canvas.Name = "Face"
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.BackgroundTransparency = 1
	canvas.Parent = holder
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = canvas

	local unit = size / 100
	for index, shape in design do
		local part = Instance.new("Frame")
		part.Name = "Shape" .. index
		part.AnchorPoint = Vector2.new(0.5, 0.5)
		part.Position = UDim2.fromScale(shape.X / 100, shape.Y / 100)
		part.Size = UDim2.fromScale(shape.W / 100, shape.H / 100)
		part.Rotation = shape.Rot or 0
		part.BackgroundColor3 = shape.Color
		part.BackgroundTransparency = shape.T or 0
		part.BorderSizePixel = 0
		part.ZIndex = index
		if (shape.R or 0) > 0 then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(shape.R :: number, 0)
			corner.Parent = part
		end
		if shape.Stroke then
			local stroke = Instance.new("UIStroke")
			stroke.Color = shape.Stroke.Color
			stroke.Thickness = math.max(1, shape.Stroke.Width * unit)
			stroke.Parent = part
		end
		part.Parent = canvas
	end

	local outline = Instance.new("UIStroke")
	outline.Color = ring or Palette.White
	outline.Thickness = math.max(2, size * 0.04)
	outline.Parent = holder
	local holderRound = Instance.new("UICorner")
	holderRound.CornerRadius = UDim.new(0.5, 0)
	holderRound.Parent = holder
	return holder
end

--[[
	The icons that slide past before stopping at `finalRole` (left to right).
	Purely for show: random icons from `pool`, never the same twice in a row,
	ending with the player's own role. Tells nothing about anyone else.
]]
function RoleIcons.reel(finalRole: string, pool: { string }, length: number, nextInt: (number, number) -> number): { string }
	local list: { string } = {}
	local last = ""
	for _ = 1, length - 1 do
		local pick = pool[nextInt(1, #pool)]
		if pick == last and #pool > 1 then
			pick = pool[(table.find(pool, pick) :: number) % #pool + 1]
		end
		table.insert(list, pick)
		last = pick
	end
	if list[#list] == finalRole and #pool > 1 then
		list[#list] = pool[(table.find(pool, finalRole) or 0) % #pool + 1]
	end
	table.insert(list, finalRole)
	return list
end

return RoleIcons
