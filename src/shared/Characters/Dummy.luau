--!strict
-- The training dummy: an average stat line with a simple M1 string. Its practice attacks
-- live in Config/DummyAttacks and are picked from the debug panel.

local Types = require(script.Parent.Parent.Types)

local function box(sx: number, sy: number, sz: number, forward: number): Types.HitboxDef
	return {
		shape = "Box",
		size = Vector3.new(sx, sy, sz),
		offset = CFrame.new(0, 0, -forward),
	}
end

local jab: Types.MoveDef = {
	id = "DummyJab",
	name = "Dummy Jab",
	kind = "melee",
	windup = 0.3,
	active = 0.08,
	recovery = 0.3,
	damage = 6,
	hitstun = 0.4,
	blockstun = 0.25,
	hitbox = box(5, 5, 5, 3),
	pose = "JabRight",
}

local dummy: Types.CharacterDef = {
	id = "Dummy",
	displayName = "Training Dummy",
	class = "Dummy",
	tier = "-",
	color = Color3.fromRGB(220, 170, 110),
	stats = { Health = 3, Damage = 3, Defense = 3, Speed = 3, Range = 3, Difficulty = 1 },
	movement = { airJumps = 0 },
	m1 = {
		string = { jab },
		forward = jab,
		air = jab,
		stringResetTime = 0.7,
		stringEndLag = 0.5,
	},
	abilities = {},
	ultChargeRate = 1,
}

return dummy
