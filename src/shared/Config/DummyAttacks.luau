--!strict
-- Attacks the training dummy can be set to throw, for practicing blocks, close blocks,
-- parries and Full Counters. Each one exercises a different rule:
--   melee   -> blockable, parryable
--   ranged  -> blockable, parryable (no reflect, no stun)
--   area    -> blockable, not parryable (Full Counter catches it only if it's an ult)
--   grab    -> can't be blocked or parried (Full Counter catches it only if it's an ult)

local Types = require(script.Parent.Parent.Types)

local function box(sx: number, sy: number, sz: number, forward: number): Types.HitboxDef
	return {
		shape = "Box",
		size = Vector3.new(sx, sy, sz),
		offset = CFrame.new(0, 0, -forward),
	}
end

local function ball(diameter: number): Types.HitboxDef
	return {
		shape = "Ball",
		size = Vector3.new(diameter, diameter, diameter),
		offset = CFrame.new(),
	}
end

local attacks: { [string]: Types.MoveDef } = {
	Jab = {
		id = "DummyJab",
		name = "Jab",
		kind = "melee",
		windup = 0.35,
		active = 0.08,
		recovery = 0.3,
		damage = 6,
		hitstun = 0.4,
		blockstun = 0.25,
		hitbox = box(5, 5, 5, 3),
		pose = "JabRight",
	},
	Finisher = {
		id = "DummyFinisher",
		name = "String Finisher",
		kind = "melee",
		windup = 0.3,
		active = 0.1,
		recovery = 0.4,
		damage = 8,
		hitstun = 0.55,
		blockstun = 0.3,
		knockback = { horizontal = 50, vertical = 20 },
		hitbox = box(5.5, 5, 5, 3),
		pose = "JabFinisher",
	},
	Heavy = {
		id = "DummyHeavy",
		name = "Heavy Swing",
		kind = "melee",
		windup = 0.7,
		active = 0.12,
		recovery = 0.5,
		damage = 14,
		hitstun = 0.6,
		blockstun = 0.35,
		knockback = { horizontal = 55, vertical = 20 },
		hitbox = box(7, 5, 6, 3.5),
		pose = "Heavy",
	},
	Arrow = {
		id = "DummyArrow",
		name = "Arrow",
		kind = "ranged",
		windup = 0.5,
		active = 0.05,
		recovery = 0.4,
		damage = 10,
		hitstun = 0.35,
		blockstun = 0.2,
		projectile = { speed = 110, range = 160, size = Vector3.new(0.4, 0.4, 3) },
		pose = "Shoot",
	},
	Explosion = {
		id = "DummyExplosion",
		name = "Explosion",
		kind = "area",
		windup = 0.8,
		active = 0.1,
		recovery = 0.6,
		damage = 12,
		hitstun = 0.5,
		blockstun = 0.3,
		knockback = { horizontal = 40, vertical = 30 },
		hitbox = ball(16),
		pose = "Slam",
	},
	Grab = {
		id = "DummyGrab",
		name = "Grab",
		kind = "grab",
		windup = 0.45,
		active = 0.1,
		recovery = 0.6,
		damage = 12,
		hitstun = 0.8,
		knockback = { horizontal = 20, vertical = 45 },
		hitbox = box(4.5, 5, 4.5, 2.8),
		pose = "Grab",
	},
	UltStrike = {
		id = "DummyUltStrike",
		name = "Ult: Strike",
		kind = "melee",
		windup = 0.9,
		active = 0.15,
		recovery = 0.8,
		damage = 30,
		hitstun = 0.8,
		blockstun = 0.5,
		knockback = { horizontal = 70, vertical = 30 },
		hitbox = box(7, 6, 7, 4),
		isUltimate = true,
		pose = "Heavy",
	},
	UltBlast = {
		id = "DummyUltBlast",
		name = "Ult: Blast",
		kind = "area",
		windup = 1.0,
		active = 0.15,
		recovery = 0.8,
		damage = 35,
		hitstun = 0.8,
		blockstun = 0.5,
		knockback = { horizontal = 60, vertical = 40 },
		hitbox = ball(22),
		isUltimate = true,
		pose = "Slam",
	},
	UltGrab = {
		id = "DummyUltGrab",
		name = "Ult: Grab",
		kind = "grab",
		windup = 0.8,
		active = 0.15,
		recovery = 0.8,
		damage = 30,
		hitstun = 1,
		knockback = { horizontal = 30, vertical = 55 },
		hitbox = box(6, 5, 6, 3),
		isUltimate = true,
		pose = "Grab",
	},
}

-- The order the debug panel cycles through. "String" is a 3-hit M1 string.
local order: { string } = { "Jab", "String", "Heavy", "Arrow", "Explosion", "Grab", "UltStrike", "UltBlast", "UltGrab" }

-- Sequences the dummy throws for one "attack". Most are a single move.
local sequences: { [string]: { string } } = {
	String = { "Jab", "Jab", "Finisher" },
}

return {
	Attacks = attacks,
	Order = order,
	Sequences = sequences,
}
