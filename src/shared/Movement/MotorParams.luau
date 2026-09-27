--!strict
-- Builds Motor params from a character's derived stats and the global movement config.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Motor = require(script.Parent.Motor)
local Stats = require(script.Parent.Parent.Combat.Stats)

local MotorParams = {}

function MotorParams.fromStats(stats: Stats.Derived): Motor.Params
	local m = GameConfig.Movement
	return {
		walkSpeed = stats.walkSpeed,
		accel = stats.accel,
		sprintAccel = stats.sprintAccel,
		decel = stats.decel,
		turnRate = stats.turnRate,
		airAccelMult = m.AirAccelMult,
		airDecelMult = m.AirDecelMult,
		airTurnMult = m.AirTurnMult,
		turnMomentumLoss = m.TurnMomentumLoss,
		minTurnFactor = m.MinTurnFactor,
		reverseAngle = math.rad(m.ReverseAngleDeg),
		knockbackFriction = m.KnockbackFriction,
		knockbackAirFriction = m.KnockbackAirFriction,
	}
end

return MotorParams
