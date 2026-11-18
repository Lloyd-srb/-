local Config = require(game.ReplicatedStorage.Shared.Config)

test("every role in RoleOrder is defined and Wolf is not pickable", function()
	for _, roleId in Config.RoleOrder do
		expect(Config.Roles[roleId] ~= nil).toBe(true)
		expect(roleId ~= "Wolf").toBe(true)
	end
	expect(#Config.RoleOrder).toBe(16)
end)

test("starter roles are free", function()
	for _, roleId in Config.RoleSelect.StarterRoles do
		expect(Config.Roles[roleId].Free).toBe(true)
	end
end)

test("every paid role costs the same: the old top price; no level gates (owner, 18 Nov 2026)", function()
	local paid = 0
	for roleId, def in Config.Roles do
		if not def.Free and roleId ~= "Wolf" then
			paid += 1
			expect(def.CoinPrice).toBe(5000)
			expect(def.RobuxPrice).toBe(399)
		end
	end
	expect(paid).toBe(13)
	for _, def in Config.Roles do
		expect(def.RequiredLevel).toBe(1)
	end
	-- Every paid role can be bought with Robux once its product id is set.
	for roleId, def in Config.Roles do
		if not def.Free and roleId ~= "Wolf" then
			expect(Config.Products.DevProducts["Role" .. roleId] ~= nil).toBe(true)
		end
	end
end)

test("hit counts from the GDD", function()
	expect(Config.Human.MaxHealth / Config.Wolf.AttackDamage).toBe(1) -- wolf: 1 hit
	expect(Config.Human.MaxHealth / Config.Pup.AttackDamage).toBe(2) -- pup: 2 hits
	expect(Config.Door.MaxHP / Config.Wolf.DoorDamage).toBe(5) -- wolf: 5 door hits
	expect(Config.Door.MaxHP / Config.Pup.DoorDamage).toBe(10) -- pup: 10 door hits
end)

test("crate and spin weights sum to 100%", function()
	local crate, spin = 0, 0
	for _, entry in Config.Crate.Loot do
		crate += entry.Weight
	end
	for _, entry in Config.DailySpin.Prizes do
		spin += entry.Weight
	end
	expect(crate).toBe(100)
	expect(spin).toBe(100)
end)

test("spin average: about 41 coins + 7 diamonds (owner halved the diamonds, 17 Nov 2026)", function()
	local coins, diamonds = 0, 0
	for _, entry in Config.DailySpin.Prizes do
		if entry.Kind == "Coins" then
			coins += entry.Amount * entry.Weight / 100
		elseif entry.Kind == "Diamonds" then
			diamonds += entry.Amount * entry.Weight / 100
		end
	end
	expect(coins).toBeNear(41, 0.01)
	expect(diamonds).toBeNear(7, 0.01)
end)
