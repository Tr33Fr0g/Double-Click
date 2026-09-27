--!strict
-- Speerrow: the fastest thing on the map. Fragile and low damage, but a skilled player
-- with great timing can outplay anyone by parrying, building stacks and turning speed
-- into damage. (Support, Difficulty 6)
--
-- Phase times below are before attack speed. Speed 6 gives +15% attack speed, so every
-- phase is divided by 1.15 at runtime.

local Types = require(script.Parent.Parent.Types)

local function box(sx: number, sy: number, sz: number, forward: number, up: number?): Types.HitboxDef
	return {
		shape = "Box",
		size = Vector3.new(sx, sy, sz),
		offset = CFrame.new(0, up or 0, -forward),
	}
end

local speerrow: Types.CharacterDef = {
	id = "Speerrow",
	displayName = "Speerrow",
	class = "Support",
	tier = "Untested",
	color = Color3.fromRGB(80, 200, 255),
	stats = { Health = 2, Damage = 1, Defense = 1, Speed = 6, Range = 2, Difficulty = 6 },

	movement = {
		-- Uncapped Speed: top sprint speed is about double the average character's (~25.6).
		sprintSpeedOverride = 52,
		airJumps = 0,
		-- Tap Shift for a fast dash dodge.
		dodge = { Speed = 72, Duration = 0.17, Cooldown = 0.55, AirDodges = 1 },
	},

	-- 3-hit string of quick, weak, short-range jabs; the 3rd hit knocks back.
	m1 = {
		string = {
			{
				id = "SpeerrowJab1",
				name = "Jab 1",
				kind = "melee",
				windup = 0.1,
				active = 0.06,
				recovery = 0.16,
				damage = 3,
				hitstun = 0.4,
				blockstun = 0.22,
				hitbox = box(4.5, 5, 4, 2.6),
				moveMult = { Windup = 0.35, Active = 0.35, Recovery = 0.6 },
				lunge = 14,
				pose = "JabRight",
			},
			{
				id = "SpeerrowJab2",
				name = "Jab 2",
				kind = "melee",
				windup = 0.1,
				active = 0.06,
				recovery = 0.16,
				damage = 3,
				hitstun = 0.4,
				blockstun = 0.22,
				hitbox = box(4.5, 5, 4, 2.6),
				moveMult = { Windup = 0.35, Active = 0.35, Recovery = 0.6 },
				lunge = 14,
				pose = "JabLeft",
			},
			{
				id = "SpeerrowJab3",
				name = "Jab 3",
				kind = "melee",
				windup = 0.14,
				active = 0.08,
				recovery = 0.3,
				damage = 4,
				hitstun = 0.55,
				blockstun = 0.26,
				knockback = { horizontal = 55, vertical = 22 },
				hitbox = box(5, 5, 4.5, 2.8),
				moveMult = { Windup = 0.3, Active = 0.3, Recovery = 0.5 },
				lunge = 18,
				pose = "JabFinisher",
			},
		},
		-- Forward: sliding kick that keeps his momentum.
		forward = {
			id = "SpeerrowSlideKick",
			name = "Sliding Kick",
			kind = "melee",
			windup = 0.1,
			active = 0.2,
			recovery = 0.3,
			damage = 4,
			hitstun = 0.45,
			blockstun = 0.25,
			hitbox = box(4.5, 3.5, 5, 2.8, -1),
			keepMomentum = true,
			moveMult = { Windup = 1, Active = 1, Recovery = 0.4 },
			pose = "SlideKick",
		},
		-- Air: downward kick.
		air = {
			id = "SpeerrowDiveKick",
			name = "Dive Kick",
			kind = "melee",
			windup = 0.1,
			active = 0.16,
			recovery = 0.26,
			damage = 4,
			hitstun = 0.45,
			blockstun = 0.24,
			hitbox = box(4.5, 5, 4.5, 1.8, -2),
			airDive = 45,
			moveMult = { Windup = 0.6, Active = 0.6, Recovery = 0.6 },
			pose = "DiveKick",
		},
		stringResetTime = 0.7,
		stringEndLag = 0.45,
	},

	abilities = {
		-- Parry has a longer base cooldown, since Good and Perfect parries refresh it. (doc)
		E = { name = "Parry", cooldown = 6 },
		R = { name = "Zap", cooldown = 3 },
		Q = { name = "Rush", cooldown = 9 },
		G = { name = "Full Counter", cooldown = 0 },
	},

	-- Full Counter charges very slowly.
	ultChargeRate = 0.35,
	kit = "Speerrow",
}

return speerrow
