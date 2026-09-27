--!strict
-- Shared type definitions for moves and characters.
-- Data modules (characters, dummy attacks) stay require-free so they can be unit tested
-- outside Roblox; the registries cast them to these types, which is where they get checked.

export type Phase = "Windup" | "Active" | "Recovery"

-- melee: swings, jabs, cones (parryable)
-- ranged: arrows and other projectiles (parryable, but nothing reflects back)
-- area: explosions and ground zones (not parryable)
-- grab: can't be blocked or parried, only dodged
export type AttackKind = "melee" | "ranged" | "area" | "grab"

export type HitboxDef = {
	shape: "Box" | "Ball",
	size: Vector3, -- for a Ball, size.X is the diameter
	offset: CFrame, -- relative to the attacker's aim frame (root position, facing the aim direction)
}

export type KnockbackDef = {
	horizontal: number,
	vertical: number,
}

export type ProjectileDef = {
	speed: number,
	range: number,
	size: Vector3,
}

export type PhaseMoveMult = {
	Windup: number,
	Active: number,
	Recovery: number,
}

export type MoveDef = {
	id: string,
	name: string,
	kind: AttackKind,
	windup: number,
	active: number,
	recovery: number,
	damage: number,
	hitstun: number,
	blockstun: number?,
	knockback: KnockbackDef?,
	stun: number?, -- a real stun on hit (follows the repeated-stun rule)
	hitbox: HitboxDef?,
	projectile: ProjectileDef?,
	isUltimate: boolean?,
	blockable: boolean?, -- default: everything except grabs
	parryable: boolean?, -- default: melee and ranged
	fullCounterable: boolean?, -- default: anything parryable, plus area and grab ults
	hyperArmor: boolean?,
	isAbility: boolean?, -- a landed ability (charges ult)
	moveMult: PhaseMoveMult?, -- how much the attacker can move during each phase
	lunge: number?, -- forward speed (studs/s) the attacker gets when the move starts
	keepMomentum: boolean?, -- the attacker keeps their current velocity (sliding moves)
	airDive: number?, -- downward speed (studs/s) for air attacks
	pose: string, -- placeholder animation (see Anim/Poses)
}

export type StatBlock = {
	Health: number,
	Damage: number,
	Defense: number,
	Speed: number,
	Range: number,
	Difficulty: number,
}

export type DodgeDef = {
	Speed: number,
	Duration: number,
	Cooldown: number,
	AirDodges: number,
}

export type MovementDef = {
	sprintSpeedOverride: number?,
	airJumps: number,
	dodge: DodgeDef?,
}

export type M1Def = {
	string: { MoveDef },
	forward: MoveDef,
	air: MoveDef,
	stringResetTime: number, -- the string restarts if you wait this long between hits
	stringEndLag: number, -- lockout after finishing the whole string
}

export type AbilityInfo = {
	name: string,
	cooldown: number,
}

export type CloseBlockLevel = {
	name: string,
	window: number, -- pressed at most this long before the hit
	color: Color3,
	blockstunMult: number, -- the defender's blockstun is multiplied by this
	attackerExtraRecovery: number, -- extra recovery the attacker suffers (the punish window)
}

export type ParryTier = {
	name: string,
	maxTime: number, -- pressed at most this long before the hit
	reflect: number, -- fraction of the incoming damage reflected back
	stacks: number, -- stacks gained (5 = max)
	cooldown: "normal" | "refresh" | "refreshAll",
	color: Color3,
}

export type CharacterDef = {
	id: string,
	displayName: string,
	class: string,
	tier: string,
	color: Color3,
	stats: StatBlock,
	movement: MovementDef,
	m1: M1Def,
	abilities: { [string]: AbilityInfo }, -- keyed by slot: E, R, Q, G
	ultChargeRate: number,
	kit: string?, -- server/client kit module name, if the character has one
}

return nil
