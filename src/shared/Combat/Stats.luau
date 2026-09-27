--!strict
-- Turns the six visible stats into the hidden stats (doc: "Stats and the stat card").
--   Weight, block strength  <- Health + Defense
--   Jump, attack speed, turn rate, walk/sprint speed <- Speed
-- Pure: pass in GameConfig.Stats and GameConfig.HealthByStat.

export type StatBlock = {
	Health: number,
	Damage: number,
	Defense: number,
	Speed: number,
	Range: number,
	Difficulty: number,
}

export type StatConfig = {
	WalkSpeedBase: number,
	WalkSpeedPerPoint: number,
	SprintMultiplier: number,
	AccelTimeBase: number,
	AccelTimePerPoint: number,
	SprintRampTime: number,
	StopTimeBase: number,
	JumpHeightBase: number,
	JumpHeightPerPoint: number,
	AttackSpeedPerPoint: number,
	TurnRateBaseDeg: number,
	TurnRatePerPointDeg: number,
	KnockbackMultBase: number,
	KnockbackMultPerPoint: number,
	BlockMeterBase: number,
	BlockMeterPerPoint: number,
	DamageMultPerPoint: number,
	DefenseReductionPerPoint: number,
}

export type Derived = {
	maxHp: number,
	weight: number,
	knockbackMult: number,
	blockMeterMax: number,
	walkSpeed: number,
	sprintSpeed: number,
	accel: number,
	sprintAccel: number,
	decel: number,
	jumpHeight: number,
	attackSpeed: number,
	turnRate: number, -- radians per second
	damageMult: number,
	defenseMult: number,
}

local Stats = {}

local function clampStat(value: number): number
	return math.clamp(math.floor(value + 0.5), 1, 6)
end

function Stats.derive(stats: StatBlock, cfg: StatConfig, healthByStat: { number }, sprintOverride: number?): Derived
	local health = clampStat(stats.Health)
	local defense = clampStat(stats.Defense)
	local speed = clampStat(stats.Speed)
	local damage = clampStat(stats.Damage)

	local weight = (health + defense) / 2
	local walkSpeed = cfg.WalkSpeedBase + cfg.WalkSpeedPerPoint * speed
	local sprintSpeed = sprintOverride or walkSpeed * cfg.SprintMultiplier
	local accelTime = math.max(0.1, cfg.AccelTimeBase + cfg.AccelTimePerPoint * speed)

	return {
		maxHp = healthByStat[health],
		weight = weight,
		knockbackMult = math.max(0.3, cfg.KnockbackMultBase + cfg.KnockbackMultPerPoint * weight),
		blockMeterMax = cfg.BlockMeterBase + cfg.BlockMeterPerPoint * (health + defense),
		walkSpeed = walkSpeed,
		sprintSpeed = sprintSpeed,
		accel = walkSpeed / accelTime,
		sprintAccel = math.max(1, sprintSpeed - walkSpeed) / cfg.SprintRampTime,
		decel = walkSpeed / cfg.StopTimeBase,
		jumpHeight = cfg.JumpHeightBase + cfg.JumpHeightPerPoint * speed,
		attackSpeed = 1 + cfg.AttackSpeedPerPoint * (speed - 3),
		turnRate = math.rad(cfg.TurnRateBaseDeg + cfg.TurnRatePerPointDeg * speed),
		damageMult = 1 + cfg.DamageMultPerPoint * (damage - 3),
		defenseMult = 1 - cfg.DefenseReductionPerPoint * (defense - 3),
	}
end

return Stats
