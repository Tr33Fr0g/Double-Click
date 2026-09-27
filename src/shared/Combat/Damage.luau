--!strict
-- Damage math. Bonuses from different sources (Speerrow's stacks, his speed at impact)
-- add together, then the attacker's Damage stat and the defender's Defense stat multiply.

local Damage = {}

-- Speerrow's Uncapped Speed: none while standing, up to `maxBonus` at full sprint.
function Damage.speedBonus(speed: number, fullSpeed: number, maxBonus: number): number
	if fullSpeed <= 0 then
		return 0
	end
	return maxBonus * math.clamp(speed / fullSpeed, 0, 1)
end

-- `bonus` is the sum of additive bonuses (0.4 = +40%).
function Damage.compute(base: number, attackerMult: number, bonus: number, defenderMult: number): number
	local raw = base * attackerMult * (1 + bonus) * defenderMult
	return math.max(0, math.floor(raw * 10 + 0.5) / 10)
end

return Damage
