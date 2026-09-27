--!strict
-- Global tuning for the Double Click beta.
-- Every number here is a placeholder for playtesting, exactly like the design doc.
-- Values marked "doc" come straight from the Master Design Document; everything else
-- is a first guess to be tuned from tester notes.

local Types = require(script.Parent.Parent.Types)

local GameConfig = {}

GameConfig.Version = "Beta 0.1"

-- One "frame" in the design notes is 1/60th of a second. All timings run on real
-- (game) time, never the player's frame rate. (doc)
GameConfig.FrameTime = 1 / 60

-- Health stat -> HP. (doc, placeholder)
GameConfig.HealthByStat = { 80, 100, 125, 150, 180, 220 }

-- How the six visible stats turn into hidden stats. The "average" character has 3 in
-- every stat, so most formulas pivot around 3.
GameConfig.Stats = {
	-- Speed -> movement
	WalkSpeedBase = 12,
	WalkSpeedPerPoint = 1.5, -- Speed 3 = 16.5 studs/s, Speed 6 = 21
	SprintMultiplier = 1.55, -- Speed 3 sprints at ~25.6 studs/s
	AccelTimeBase = 0.45, -- seconds from standing to walk speed at Speed 0
	AccelTimePerPoint = -0.04, -- faster characters get going sooner
	SprintRampTime = 0.8, -- seconds from walk speed to sprint speed
	StopTimeBase = 0.3, -- seconds to stop from walk speed on the ground
	JumpHeightBase = 5,
	JumpHeightPerPoint = 0.8, -- Speed 3 = 7.4 studs, Speed 6 = 9.8
	AttackSpeedPerPoint = 0.05, -- +5% attack speed per Speed point above 3
	TurnRateBaseDeg = 360,
	TurnRatePerPointDeg = 60, -- Speed 3 = 540 deg/s, Speed 6 = 720 deg/s

	-- Health + Defense -> weight and block strength
	KnockbackMultBase = 1.3,
	KnockbackMultPerPoint = -0.1, -- per point of (Health + Defense) / 2
	BlockMeterBase = 50,
	BlockMeterPerPoint = 10, -- per point of Health + Defense

	-- Damage and Defense
	DamageMultPerPoint = 0.1, -- Damage 1 = x0.8, Damage 6 = x1.3
	DefenseReductionPerPoint = 0.05, -- Defense 1 takes x1.1, Defense 6 takes x0.85
}

GameConfig.Movement = {
	AirAccelMult = 0.35,
	AirDecelMult = 0.12, -- you keep your momentum in the air
	AirTurnMult = 0.5,
	TurnMomentumLoss = 0.5, -- fraction of speed lost by a full 180 degree turn at the turn rate
	MinTurnFactor = 0.35, -- at very high speed you turn at no less than 35% of your turn rate
	ReverseAngleDeg = 150, -- sharper than this and you have to brake before turning
	KnockbackFriction = 45,
	KnockbackAirFriction = 8,
	FacingTurnRateDeg = 900,
	BlockMoveMult = 0.45,

	WallDetectDistance = 1.9,
	WallMaxNormalY = 0.3, -- any surface steeper than this counts as a wall (doc: "steep enough")
	WallSlideSpeed = 9,
	WallJumpHeight = 7,
	WallJumpPush = 24,
	WallJumpLockout = 0.2, -- seconds of reduced air control after a wall jump

	CoyoteTime = 0.1,
	JumpBuffer = 0.12,

	Dodge = {
		Speed = 55,
		Duration = 0.22,
		Cooldown = 0.7,
		AirDodges = 1,
	},

	ForwardInputDot = 0.5, -- how "forward" the input must be for a Forward M1
	ForwardSpeedFraction = 0.4, -- ...and how fast you must be going (fraction of walk speed)

	KillPlaneY = -80,
}

GameConfig.Combat = {
	-- Close-block levels, checked in order. (doc)
	CloseBlock = {
		{
			name = "Perfect",
			window = 0.1,
			color = Color3.fromRGB(255, 200, 40), -- gold
			blockstunMult = 0,
			attackerExtraRecovery = 0.28,
		},
		{
			name = "Great",
			window = 0.2,
			color = Color3.fromRGB(215, 220, 230), -- silver
			blockstunMult = 0.35,
			attackerExtraRecovery = 0.22,
		},
		{
			name = "Good",
			window = 0.3,
			color = Color3.fromRGB(70, 150, 255), -- blue
			blockstunMult = 0.65,
			attackerExtraRecovery = 0.12,
		},
	} :: { Types.CloseBlockLevel },

	BlockArcDegrees = 180, -- a block covers the front half of the character
	BlockRepressDelay = 0.15, -- after letting go of F you can't block again for this long
	DefaultBlockstunMult = 0.6, -- used when a move doesn't list its own blockstun
	BlockMeterDrainPerDamage = 1.5,
	BlockMeterRegenDelay = 1.5,
	BlockMeterRegenRate = 25,
	GuardBreakStun = 1.0,

	-- Repeated-stun rule. (doc)
	Stun = {
		ChainWindow = 3,
		Multipliers = { 1, 0.75, 0.5, 0.25 },
		Immunity = 2,
	},

	WallStun = 0.4, -- (doc)
	WallStunCheckTime = 0.5, -- how long after knockback a wall hit still counts
	WallStunDistance = 2.4,
	WallStunMinSpeed = 14,
	KnockbackLock = 0.35, -- seconds the victim has no control after knockback

	M1BufferWindow = 0.25, -- an M1 pressed this close to the end of an attack is queued
	LagCompensationMax = 0.2, -- how far back a client's block/parry press can be credited
	DownedTime = 3,

	UltMax = 100,
	UltPerDamage = 1.0,
	UltPerAbilityHit = 4,
}

GameConfig.Camera = {
	Distance = 11,
	ShoulderOffset = Vector3.new(2.3, 1.2, 0),
	PivotHeight = 1.6,
	Sensitivity = 0.22, -- degrees per pixel
	PitchMinDeg = -70,
	PitchMaxDeg = 65,
	FollowSharpness = 20,
	FieldOfView = 70,
	SprintFieldOfView = 80,
	CollisionRadius = 0.6,
	LockOn = {
		Range = 90,
		MaxAngleDeg = 40,
		TurnSharpness = 12,
	},
}

GameConfig.Debug = {
	-- Debug mode only works in private and test servers, never in ranked. (doc)
	AllowInStudio = true,
	AllowInPrivateServers = true,
	TestPlaceIds = {} :: { number }, -- add dedicated test place ids here
	ForceEnable = false,
	TimeScales = { 1, 0.5, 0.25, 0.1 },
	FrameStep = 1 / 60,
	Colors = {
		Windup = Color3.fromRGB(255, 220, 40), -- yellow (doc)
		Active = Color3.fromRGB(255, 50, 50), -- red (doc)
		Recovery = Color3.fromRGB(60, 120, 255), -- blue (doc)
		Hurtbox = Color3.fromRGB(80, 255, 120),
	},
}

return GameConfig
