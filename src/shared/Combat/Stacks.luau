--!strict
-- Speerrow's stacks (doc: "Passive, Stacks").
--   Gaining: parries give 1/2/3/5 by tier, each Rush hit gives 0.5. Max 5.
--   Effect: +20% damage per whole stack. Rush speed counts half stacks (+5% per half).
--   Losing: 1 stack per hit that lands on him. Everything drops 10s after the last gain;
--   losing a stack doesn't reset that timer, only gaining does.

export type Config = {
	Max: number,
	DamagePerStack: number,
	LossPerHit: number,
	Duration: number,
	RushSpeedPerHalfStack: number,
}

export type State = {
	value: number,
	lastGainAt: number,
}

local Stacks = {}

function Stacks.new(): State
	return { value = 0, lastGainAt = -math.huge }
end

function Stacks.reset(state: State)
	state.value = 0
	state.lastGainAt = -math.huge
end

function Stacks.gain(state: State, amount: number, now: number, cfg: Config)
	if amount <= 0 then
		return
	end
	state.value = math.min(cfg.Max, state.value + amount)
	state.lastGainAt = now
end

function Stacks.setMax(state: State, now: number, cfg: Config)
	state.value = cfg.Max
	state.lastGainAt = now
end

function Stacks.loseOnHit(state: State, cfg: Config)
	state.value = math.max(0, state.value - cfg.LossPerHit)
end

-- Drops every stack once the timer runs out. Returns true if stacks were dropped.
function Stacks.update(state: State, now: number, cfg: Config): boolean
	if state.value > 0 and now - state.lastGainAt >= cfg.Duration then
		state.value = 0
		return true
	end
	return false
end

function Stacks.whole(state: State): number
	return math.floor(state.value + 1e-9)
end

function Stacks.damageMultiplier(state: State, cfg: Config): number
	return 1 + cfg.DamagePerStack * Stacks.whole(state)
end

function Stacks.rushSpeedMultiplier(state: State, cfg: Config): number
	local halves = math.floor(state.value * 2 + 1e-9)
	return 1 + cfg.RushSpeedPerHalfStack * halves
end

function Stacks.expiresIn(state: State, now: number, cfg: Config): number
	if state.value <= 0 then
		return 0
	end
	return math.max(0, cfg.Duration - (now - state.lastGainAt))
end

return Stacks
