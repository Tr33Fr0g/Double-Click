--!strict
-- The repeated-stun rule (doc: "Stuns and status effects"):
--   1st stun 100%, 2nd 75%, 3rd 50%, 4th 25% (each within 3s of the last),
--   then immune to stuns for 2s. The chain resets after 3s with no stuns, or after the
--   immunity ends.
-- Immunity starts when the 4th stun ends, so the 4th stun still lands.

export type Config = {
	ChainWindow: number,
	Multipliers: { number },
	Immunity: number,
}

export type State = {
	count: number,
	lastAt: number,
	immuneFrom: number,
	immuneUntil: number,
}

export type ApplyResult = {
	duration: number,
	index: number, -- which stun in the chain this was (1-4), 0 if immune
	immune: boolean,
}

local StunChain = {}

local NEVER = -math.huge

function StunChain.new(): State
	return { count = 0, lastAt = NEVER, immuneFrom = math.huge, immuneUntil = NEVER }
end

function StunChain.reset(state: State)
	state.count = 0
	state.lastAt = NEVER
	state.immuneFrom = math.huge
	state.immuneUntil = NEVER
end

local function refresh(state: State, now: number, cfg: Config)
	if state.immuneUntil ~= NEVER and now >= state.immuneUntil then
		-- Immunity is over: start a fresh chain.
		StunChain.reset(state)
	elseif state.count > 0 and state.immuneUntil == NEVER and now - state.lastAt > cfg.ChainWindow then
		state.count = 0
	end
end

function StunChain.isImmune(state: State, now: number): boolean
	return now >= state.immuneFrom and now < state.immuneUntil
end

-- Applies a stun of `base` seconds at time `now` and returns how long it actually lasts.
function StunChain.apply(state: State, now: number, base: number, cfg: Config): ApplyResult
	refresh(state, now, cfg)
	if state.immuneUntil ~= NEVER then
		-- Either immune right now, or the 4th stun is still running (which also can't be
		-- stacked on).
		return { duration = 0, index = 0, immune = true }
	end

	state.count += 1
	state.lastAt = now
	local multipliers = cfg.Multipliers
	local index = math.min(state.count, #multipliers)
	local duration = base * multipliers[index]

	if state.count >= #multipliers then
		state.immuneFrom = now + duration
		state.immuneUntil = now + duration + cfg.Immunity
	end

	return { duration = duration, index = index, immune = false }
end

-- For the debug overlay: stuns so far in the current chain and seconds of immunity left.
function StunChain.peek(state: State, now: number, cfg: Config): (number, number)
	refresh(state, now, cfg)
	local immuneLeft = 0
	if StunChain.isImmune(state, now) then
		immuneLeft = state.immuneUntil - now
	end
	return state.count, immuneLeft
end

return StunChain
