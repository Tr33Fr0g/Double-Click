--!strict
-- Tuning for Speerrow's passives and abilities. Numbers marked "doc" come from the design
-- doc; the rest are placeholders. Cooldowns live in Speerrow.abilities.

local Types = require(script.Parent.Parent.Types)

local parryTiers: { Types.ParryTier } = {
	{
		name = "Perfect",
		maxTime = 0.25,
		reflect = 0.75,
		stacks = 5,
		cooldown = "refreshAll",
		color = Color3.fromRGB(255, 200, 40),
	},
	{
		name = "Good",
		maxTime = 0.42,
		reflect = 0.35,
		stacks = 3,
		cooldown = "refresh",
		color = Color3.fromRGB(215, 220, 230),
	},
	{
		name = "Basic",
		maxTime = 0.58,
		reflect = 0.2,
		stacks = 2,
		cooldown = "normal",
		color = Color3.fromRGB(70, 150, 255),
	},
	{
		name = "Weak",
		maxTime = 0.73,
		reflect = 0.15,
		stacks = 1,
		cooldown = "normal",
		color = Color3.fromRGB(160, 160, 170),
	},
}

-- R: very short-range jab with almost no wind-up.
local zap: Types.MoveDef = {
	id = "SpeerrowZap",
	name = "Zap",
	kind = "melee",
	windup = 0.03,
	active = 0.06,
	recovery = 0.18,
	damage = 2,
	hitstun = 0.2,
	stun = 0.5, -- (doc)
	blockstun = 0.15,
	isAbility = true,
	hitbox = {
		shape = "Box",
		size = Vector3.new(3.5, 5, 3),
		offset = CFrame.new(0, 0, -2),
	},
	moveMult = { Windup = 0.2, Active = 0.2, Recovery = 0.5 },
	lunge = 10,
	pose = "Zap",
}

-- A Rush hit, resolved like a melee attack (so it can be blocked, parried and countered).
local rushHit: Types.MoveDef = {
	id = "SpeerrowRush",
	name = "Rush",
	kind = "melee",
	windup = 0,
	active = 0,
	recovery = 0,
	damage = 4,
	hitstun = 0.35,
	blockstun = 0.2,
	isAbility = true,
	pose = "Rush",
}

return {
	Stacks = {
		Max = 5, -- (doc)
		DamagePerStack = 0.2, -- +20% damage per whole stack (doc)
		LossPerHit = 1, -- loses 1 stack per hit that lands on him (doc)
		Duration = 10, -- all stacks drop 10s after the last stack gained (doc)
		RushGain = 0.5, -- each Rush hit gives 0.5 (doc)
		RushSpeedPerHalfStack = 0.05, -- +5% Rush speed per half stack, up to +50% (doc)
	},

	UncappedSpeed = {
		MaxBonus = 0.5, -- up to +50% damage at full sprint (doc)
	},

	-- E: press before an enemy's hit lands. The rest of the incoming damage is cancelled
	-- in every tier. Tiers are checked fastest first; the doc's small gaps between tiers
	-- (0.25-0.27, 0.42-0.43, 0.58-0.6) fall into the next slower tier.
	Parry = {
		Stance = 0.73,
		Tiers = parryTiers,
		PerfectUltWindow = 0.08, -- a Perfect within 0.08s also gives +50% ult charge (doc)
		PerfectUltBonus = 50,
		MeleeStun = 0.3, -- parrying a melee attacker stuns them (doc)
		WhiffRecovery = 0.25,
		MoveMult = 0.5,
	},

	Zap = zap,

	-- Q: launches like a bullet toward wherever you're looking and bounces.
	Rush = {
		Speed = 110,
		LandTime = 0.25, -- (doc: 0.1-0.4s, to tune)
		CharacterLength = 5,
		FreeFlightLengths = 2.5, -- (doc: 2-3 character-lengths)
		MaxDuration = 4,
		MaxBounces = 12,
		BlockedStun = 0.6, -- (doc)
		HitRadius = 2.4,
		SurfaceRadius = 1.4,
		PullBackSpeed = 28,
		PullBackTime = 0.15,
		SameTargetDelay = 0.4,
		ServerTimeout = 6,
		Move = rushHit,
	},

	-- G: works only in the perfect window.
	FullCounter = {
		Window = 0.25, -- (doc)
		ReflectMult = 5, -- (doc)
		UltStun = 3, -- stuns every enemy on the map if he counters an ultimate (doc)
		WhiffRecovery = 0.5,
	},
}
