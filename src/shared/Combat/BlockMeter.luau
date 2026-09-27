--!strict
-- The hidden block meter (doc: "Blocking (F)"). It wears down as blocked hits land and
-- breaks faster on fragile characters. When it breaks you're briefly stunned.
-- Close blocks never save meter, even at Perfect, so the drain ignores the close-block level.

export type Config = {
	BlockMeterDrainPerDamage: number,
	BlockMeterRegenDelay: number,
	BlockMeterRegenRate: number,
}

export type State = {
	value: number,
	max: number,
	lastHitAt: number,
}

local BlockMeter = {}

function BlockMeter.new(max: number): State
	return { value = max, max = max, lastHitAt = -math.huge }
end

function BlockMeter.refill(state: State)
	state.value = state.max
end

-- Returns true if this hit broke the block.
function BlockMeter.drain(state: State, damage: number, now: number, cfg: Config): boolean
	state.lastHitAt = now
	state.value = math.max(0, state.value - damage * cfg.BlockMeterDrainPerDamage)
	return state.value <= 0
end

function BlockMeter.update(state: State, dt: number, now: number, blocking: boolean, cfg: Config)
	if blocking or state.value >= state.max then
		return
	end
	if now - state.lastHitAt < cfg.BlockMeterRegenDelay then
		return
	end
	state.value = math.min(state.max, state.value + cfg.BlockMeterRegenRate * dt)
end

return BlockMeter
