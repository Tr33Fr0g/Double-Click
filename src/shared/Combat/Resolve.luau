--!strict
-- Decides what happens when an attack reaches a defender, in priority order:
--   1. Ignored      (defender is intangible or already down)
--   2. FullCounter  (Speerrow's G stance, perfect window only)
--   3. Parry        (Speerrow's E stance)
--   4. Block        (holding F and facing the attacker)
--   5. Hit
-- Parry rules (doc): melee and ranged can be parried; area attacks and grabs can't.
-- Full Counter also catches area ults and grab-style ults. Grabs can't be blocked.

export type AttackKind = "melee" | "ranged" | "area" | "grab"

export type AttackFlags = {
	kind: AttackKind,
	isUltimate: boolean?,
	blockable: boolean?,
	parryable: boolean?,
	fullCounterable: boolean?,
}

export type DefenderView = {
	intangible: boolean,
	downed: boolean,
	counterStart: number?,
	parryStart: number?,
	blocking: boolean,
	blockStart: number?,
	facingDot: number, -- dot(defender facing, direction to attacker)
}

export type Config = {
	fullCounterWindow: number,
	parryStance: number,
	blockArcDot: number,
}

export type Result = "Ignored" | "FullCounter" | "Parry" | "Block" | "Hit"

export type Outcome = {
	result: Result,
	timing: number, -- seconds between the press and the impact (0 for Hit / Ignored)
}

local Resolve = {}

function Resolve.isBlockable(attack: AttackFlags): boolean
	if attack.blockable ~= nil then
		return attack.blockable
	end
	return attack.kind ~= "grab"
end

function Resolve.isParryable(attack: AttackFlags): boolean
	if attack.parryable ~= nil then
		return attack.parryable
	end
	return attack.kind == "melee" or attack.kind == "ranged"
end

function Resolve.isFullCounterable(attack: AttackFlags): boolean
	if attack.fullCounterable ~= nil then
		return attack.fullCounterable
	end
	if Resolve.isParryable(attack) then
		return true
	end
	return attack.isUltimate == true and (attack.kind == "area" or attack.kind == "grab")
end

-- The arc a block covers, as the minimum dot product between facing and the attacker.
function Resolve.arcDot(arcDegrees: number): number
	return math.cos(math.rad(arcDegrees / 2))
end

function Resolve.decide(attack: AttackFlags, defender: DefenderView, now: number, cfg: Config): Outcome
	if defender.intangible or defender.downed then
		return { result = "Ignored", timing = 0 }
	end

	local counterStart = defender.counterStart
	if counterStart and Resolve.isFullCounterable(attack) then
		local t = now - counterStart
		if t >= 0 and t <= cfg.fullCounterWindow + 1e-9 then
			return { result = "FullCounter", timing = t }
		end
	end

	local parryStart = defender.parryStart
	if parryStart and Resolve.isParryable(attack) then
		local t = now - parryStart
		if t >= 0 and t <= cfg.parryStance + 1e-9 then
			return { result = "Parry", timing = t }
		end
	end

	-- A block pressed after the impact (possible when a hit is timed to the scheduled start
	-- of the active phase) doesn't count.
	local blockStart = defender.blockStart
	if
		defender.blocking
		and blockStart
		and now - blockStart >= -1e-9
		and Resolve.isBlockable(attack)
		and defender.facingDot >= cfg.blockArcDot - 1e-6
	then
		return { result = "Block", timing = math.max(0, now - blockStart) }
	end

	return { result = "Hit", timing = 0 }
end

return Resolve
