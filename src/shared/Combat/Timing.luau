--!strict
-- Close-block and parry timing. "Timing" is always how long before the hit landed the
-- button was pressed, in seconds of game time.

local Types = require(script.Parent.Parent.Types)

type CloseBlockLevel = Types.CloseBlockLevel
type ParryTier = Types.ParryTier

local Timing = {}

Timing.FramesPerSecond = 60

-- Returns the close-block level for a block pressed `t` seconds before impact, or nil for
-- a normal block. Levels are checked in order, so list the tightest window first.
function Timing.closeBlockLevel(t: number, levels: { CloseBlockLevel }): CloseBlockLevel?
	if t < 0 then
		return nil
	end
	for _, level in levels do
		if t <= level.window + 1e-9 then
			return level
		end
	end
	return nil
end

-- Returns the parry tier for a parry pressed `t` seconds before impact, or nil if the
-- press was too early (outside every tier).
function Timing.parryTier(t: number, tiers: { ParryTier }): ParryTier?
	if t < 0 then
		return nil
	end
	for _, tier in tiers do
		if t <= tier.maxTime + 1e-9 then
			return tier
		end
	end
	return nil
end

function Timing.frames(t: number): number
	return math.floor(t * Timing.FramesPerSecond + 0.5)
end

-- "Close block: Great, 0.17s (10 frames) before impact."
function Timing.describe(label: string, result: string, t: number): string
	local frames = Timing.frames(t)
	local unit = if frames == 1 then "frame" else "frames"
	return string.format("%s: %s, %.2fs (%d %s) before impact.", label, result, t, frames, unit)
end

return Timing
