--!nocheck
local T = require("./lib")
local GameConfig = require("../src/shared/Config/GameConfig")
local Stats = require("../src/shared/Combat/Stats")
local Motor = require("../src/shared/Movement/Motor")
local Speerrow = require("../src/shared/Characters/Speerrow")

local derived =
	Stats.derive(Speerrow.stats, GameConfig.Stats, GameConfig.HealthByStat, Speerrow.movement.sprintSpeedOverride)
local m = GameConfig.Movement
local params = {
	walkSpeed = derived.walkSpeed,
	accel = derived.accel,
	sprintAccel = derived.sprintAccel,
	decel = derived.decel,
	turnRate = derived.turnRate,
	airAccelMult = m.AirAccelMult,
	airDecelMult = m.AirDecelMult,
	airTurnMult = m.AirTurnMult,
	turnMomentumLoss = m.TurnMomentumLoss,
	minTurnFactor = m.MinTurnFactor,
	reverseAngle = math.rad(m.ReverseAngleDeg),
	knockbackFriction = m.KnockbackFriction,
	knockbackAirFriction = m.KnockbackAirFriction,
}

local DT = 1 / 60
local forward = Vector3.new(0, 0, -1)
local right = Vector3.new(1, 0, 0)

local function run(state, seconds, direction, speed, grounded, startTime)
	local now = startTime or 0
	for _ = 1, math.floor(seconds / DT + 0.5) do
		now += DT
		Motor.step(state, DT, now, { direction = direction, targetSpeed = speed, grounded = grounded ~= false }, params)
	end
	return now
end

T.describe("Weighty movement", function()
	T.it("ramps up to walk speed instead of reaching it instantly", function()
		local s = Motor.new()
		run(s, DT, forward, params.walkSpeed)
		T.truthy(s.velocity.Magnitude < params.walkSpeed * 0.2, "first frame was too fast")
		run(s, 0.4, forward, params.walkSpeed)
		T.near(s.velocity.Magnitude, params.walkSpeed, 1e-3)
	end)
	T.it("builds up to sprint speed over time", function()
		local s = Motor.new()
		run(s, 0.4, forward, derived.sprintSpeed)
		local early = s.velocity.Magnitude
		T.truthy(early < derived.sprintSpeed * 0.8, "reached sprint too quickly: " .. early)
		run(s, 1.5, forward, derived.sprintSpeed)
		T.near(s.velocity.Magnitude, derived.sprintSpeed, 1e-3)
	end)
	T.it("stopping takes a moment", function()
		local s = Motor.new()
		run(s, 2, forward, derived.sprintSpeed)
		run(s, 0.2, Vector3.zero, 0)
		T.truthy(s.velocity.Magnitude > 5, "stopped too quickly")
		run(s, 1.5, Vector3.zero, 0)
		T.eq(s.velocity.Magnitude, 0)
	end)
	T.it("keeps momentum in the air", function()
		local s = Motor.new()
		run(s, 2, forward, derived.sprintSpeed)
		run(s, 0.3, Vector3.zero, 0, false)
		T.truthy(s.velocity.Magnitude > derived.sprintSpeed * 0.8)
	end)
	T.it("turning hard at speed costs momentum and takes time", function()
		local s = Motor.new()
		run(s, 2, forward, derived.sprintSpeed)
		run(s, DT * 3, right, derived.sprintSpeed)
		local dir = s.velocity.Unit
		T.truthy(dir:Dot(right) < 0.9, "turned too sharply")
		T.truthy(s.velocity.Magnitude < derived.sprintSpeed, "no momentum lost")
		run(s, 1.5, right, derived.sprintSpeed)
		T.truthy(s.velocity.Unit:Dot(right) > 0.999, "never finished the turn")
	end)
	T.it("reversing at speed brakes before turning around", function()
		local s = Motor.new()
		run(s, 2, forward, derived.sprintSpeed)
		run(s, DT * 5, -forward, derived.sprintSpeed)
		T.truthy(s.velocity.Unit:Dot(forward) > 0.99, "flipped direction instantly")
		T.truthy(s.velocity.Magnitude < derived.sprintSpeed)
	end)
end)

T.describe("Dodge and knockback", function()
	T.it("dodge holds its velocity, then flows into a sprint", function()
		local s = Motor.new()
		Motor.impulse(s, forward * 72, 0, 0.17, "dodge")
		run(s, 0.15, right, derived.sprintSpeed)
		T.near(s.velocity.Magnitude, 72, 1e-6)
		T.truthy(s.velocity.Unit:Dot(forward) > 0.999, "dodge was steerable")
		run(s, 0.1, forward, derived.sprintSpeed, true, 0.15)
		T.truthy(s.velocity.Magnitude > derived.sprintSpeed * 0.9, "lost the sprint after dodging")
	end)
	T.it("knockback ignores input and bleeds off with friction", function()
		local s = Motor.new()
		Motor.impulse(s, right * 50, 0, 0.35, "knockback")
		run(s, 0.2, forward, params.walkSpeed)
		T.truthy(s.velocity.Unit:Dot(right) > 0.999)
		T.near(s.velocity.Magnitude, 50 - params.knockbackFriction * 0.2, 0.5)
	end)
	T.it("reconcile drops speed the character isn't actually moving at", function()
		local s = Motor.new()
		run(s, 2, forward, derived.sprintSpeed)
		Motor.reconcile(s, Vector3.zero, DT, 10, params)
		T.truthy(s.velocity.Magnitude < 5, "kept stored speed against a wall")
	end)
end)
