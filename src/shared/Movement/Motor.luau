--!strict
-- Weighty planar movement (doc: "Movement feels weighty, like Elden Ring").
--   * You ramp up to top speed instead of reaching it instantly.
--   * Stopping takes a moment.
--   * Turning is limited by your turn rate; turning hard at speed costs momentum, and
--     reversing at speed means braking first.
-- The motor only tracks horizontal velocity in "game units" (unscaled by slow motion).
-- A driver feeds its output to a Humanoid (Humanoid:Move + WalkSpeed).

export type Params = {
	walkSpeed: number,
	accel: number,
	sprintAccel: number,
	decel: number,
	turnRate: number, -- radians per second
	airAccelMult: number,
	airDecelMult: number,
	airTurnMult: number,
	turnMomentumLoss: number,
	minTurnFactor: number,
	reverseAngle: number, -- radians
	knockbackFriction: number,
	knockbackAirFriction: number,
}

export type Input = {
	direction: Vector3, -- planar unit vector, or zero for no input
	targetSpeed: number,
	grounded: boolean,
}

export type LockKind = "dodge" | "knockback" | "slide"

export type State = {
	velocity: Vector3,
	lockUntil: number,
	lockKind: LockKind?,
}

local Motor = {}

local EPSILON = 1e-4

local function planar(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Rotates planar unit vector `from` toward `to` by at most `maxAngle` radians.
local function rotateToward(from: Vector3, to: Vector3, maxAngle: number): (Vector3, number)
	local dot = math.clamp(from:Dot(to), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxAngle then
		return to, angle
	end
	-- Right-handed rotation about +Y; the sign comes from cross(from, to).Y.
	local crossY = from.Z * to.X - from.X * to.Z
	local theta = if crossY >= 0 then maxAngle else -maxAngle
	local c, s = math.cos(theta), math.sin(theta)
	local x = from.X * c + from.Z * s
	local z = -from.X * s + from.Z * c
	return Vector3.new(x, 0, z).Unit, maxAngle
end

Motor.rotateToward = rotateToward

function Motor.new(): State
	return { velocity = Vector3.zero, lockUntil = -math.huge, lockKind = nil }
end

function Motor.isLocked(state: State, now: number): boolean
	return now < state.lockUntil
end

-- Sets the velocity and ignores input for `duration` seconds.
-- dodge: velocity stays constant. knockback: velocity bleeds off with friction.
-- slide: velocity stays constant (sliding attacks keep their momentum).
function Motor.impulse(state: State, velocity: Vector3, now: number, duration: number, kind: LockKind)
	state.velocity = planar(velocity)
	state.lockUntil = now + duration
	state.lockKind = kind
end

-- Keeps the current velocity for `duration` seconds without changing it.
function Motor.hold(state: State, now: number, duration: number)
	state.lockUntil = math.max(state.lockUntil, now + duration)
	state.lockKind = "slide"
end

function Motor.clearLock(state: State)
	state.lockUntil = -math.huge
	state.lockKind = nil
end

function Motor.stop(state: State)
	state.velocity = Vector3.zero
	Motor.clearLock(state)
end

function Motor.step(state: State, dt: number, now: number, input: Input, params: Params): Vector3
	local velocity = state.velocity
	local speed = velocity.Magnitude

	if now < state.lockUntil then
		if state.lockKind == "knockback" and speed > EPSILON then
			local friction = if input.grounded then params.knockbackFriction else params.knockbackAirFriction
			local newSpeed = math.max(0, speed - friction * dt)
			state.velocity = velocity.Unit * newSpeed
		end
		return state.velocity
	end
	state.lockKind = nil

	local accelMult = if input.grounded then 1 else params.airAccelMult
	local decelMult = if input.grounded then 1 else params.airDecelMult
	local direction = input.direction
	local hasInput = direction.Magnitude > EPSILON and input.targetSpeed > EPSILON

	if not hasInput then
		local newSpeed = math.max(0, speed - params.decel * decelMult * dt)
		state.velocity = if newSpeed > EPSILON then velocity.Unit * newSpeed else Vector3.zero
		return state.velocity
	end

	direction = planar(direction).Unit
	local target = input.targetSpeed
	local newDirection: Vector3

	if speed < 0.5 then
		-- From (almost) standing you set off in the direction you want.
		newDirection = direction
	else
		local current = velocity.Unit
		local angle = math.acos(math.clamp(current:Dot(direction), -1, 1))
		if angle > params.reverseAngle and speed > params.walkSpeed * 0.3 then
			-- Too sharp to turn at this speed: brake first.
			local newSpeed = math.max(0, speed - params.decel * decelMult * 1.25 * dt)
			state.velocity = current * newSpeed
			return state.velocity
		end

		-- The faster you go, the wider you turn.
		local speedFactor = math.clamp(params.walkSpeed / speed, params.minTurnFactor, 1)
		local turnRate = params.turnRate * speedFactor * (if input.grounded then 1 else params.airTurnMult)
		local turned
		newDirection, turned = rotateToward(current, direction, turnRate * dt)
		speed *= 1 - (turned / math.pi) * params.turnMomentumLoss
	end

	if speed < target then
		local rate = if speed < params.walkSpeed then params.accel else params.sprintAccel
		speed = math.min(target, speed + rate * accelMult * dt)
	else
		speed = math.max(target, speed - params.decel * decelMult * dt)
	end

	state.velocity = newDirection * speed
	return state.velocity
end

-- After physics: if something (a wall, a slope) stopped the character, don't let the
-- motor keep "stored" speed it isn't actually moving at.
function Motor.reconcile(state: State, actual: Vector3, dt: number, now: number, params: Params)
	if now < state.lockUntil then
		return
	end
	local speed = state.velocity.Magnitude
	if speed <= EPSILON then
		return
	end
	local actualSpeed = planar(actual).Magnitude
	local allowed = actualSpeed + math.max(params.accel, params.sprintAccel) * dt * 2 + 1
	if speed > allowed then
		state.velocity = state.velocity.Unit * allowed
	end
end

return Motor
