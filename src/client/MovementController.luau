--!strict
-- Weighty movement for the local character (doc: "Movement").
--   * Acceleration up to top speed; stopping and turning take a moment (Motor).
--   * Shift tap = dodge, fired the instant Shift is pressed (no invincibility). If Shift is
--     still held when the dodge ends, the character flows straight into a sprint.
--   * Shift hold = unlimited sprint. Jump height follows Speed.
--   * Walls and trees: slide down them in the air and wall jump off them.
-- The client owns its character's physics; the server only enforces combat states
-- through the DC_MoveMult / DC_State attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Attr = require(Shared.Util.Attr)
local Clock = require(Shared.Util.Clock)
local GameConfig = require(Shared.Config.GameConfig)
local Motor = require(Shared.Movement.Motor)
local MotorParams = require(Shared.Movement.MotorParams)

local CameraController = require(script.Parent.CameraController)
local Events = require(script.Parent.Events)
local Input = require(script.Parent.Input)
local Me = require(script.Parent.Me)

local M = GameConfig.Movement

local MovementController = {}

local motor = Motor.new()
local params: Motor.Params? = nil
local facing = Vector3.new(0, 0, -1)
local actionFacing: Vector3? = nil
local external = false -- an ability (Rush) is flying the character
local externalStep: ((dt: number, now: number) -> ())? = nil

local shiftHeld = false
local sprinting = false
local dodgeReadyAt = -math.huge
local dodgeUntil = -math.huge
local airDodgesUsed = 0
local airJumpsUsed = 0
local lastGroundedAt = -math.huge
local jumpPressedAt = -math.huge
local wallNormal: Vector3? = nil
local lastReportedSprint = false
local lastReportedAir = false
local pausedVelocity: Vector3? = nil

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Include

local WALL_DIRECTIONS = {}
for i = 0, 7 do
	local angle = i * math.pi / 4
	table.insert(WALL_DIRECTIONS, Vector3.new(math.cos(angle), 0, math.sin(angle)))
end

local FREE_STATES = { Free = true, Dodging = true }

local function planar(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v: Vector3, fallback: Vector3): Vector3
	return if v.Magnitude > 1e-3 then v.Unit else fallback
end

local function dodgeDef()
	local body = Me.body
	return if body and body.def.movement.dodge then body.def.movement.dodge else M.Dodge
end

-- Camera-relative movement input as a world direction (zero if none).
function MovementController.inputDirection(): Vector3
	local move = Input.moveVector()
	if move.Magnitude < 1e-3 then
		return Vector3.zero
	end
	local yaw = CameraController.yaw()
	local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	return (forward * move.Y + right * move.X).Unit
end

function MovementController.velocity(): Vector3
	return motor.velocity
end

function MovementController.isGrounded(): boolean
	local body = Me.body
	return body ~= nil and body.humanoid.FloorMaterial ~= Enum.Material.Air
end

function MovementController.isSprinting(): boolean
	return sprinting
end

function MovementController.motor(): Motor.State
	return motor
end

-- Faces `direction` right away and holds it while an action plays out.
function MovementController.faceAction(direction: Vector3)
	local flat = planar(direction)
	if flat.Magnitude > 1e-3 then
		actionFacing = flat.Unit
		facing = flat.Unit
	end
end

function MovementController.setFacing(direction: Vector3)
	local flat = planar(direction)
	local body = Me.body
	if flat.Magnitude > 1e-3 then
		facing = flat.Unit
		if body then
			body.align.CFrame = CFrame.lookAlong(Vector3.zero, facing)
		end
	end
end

-- Lets an ability (Rush) take over the character. `step` runs every frame instead of
-- normal movement until released.
function MovementController.setExternal(on: boolean, step: ((dt: number, now: number) -> ())?)
	external = on
	externalStep = if on then step else nil
end

function MovementController.lunge(direction: Vector3, speed: number)
	local flat = planar(direction)
	if flat.Magnitude < 1e-3 or speed <= 0 then
		return
	end
	Motor.impulse(motor, flat.Unit * speed, Clock.now(), 0.08, "dodge")
end

-- Sliding attacks keep their momentum for `duration` seconds.
function MovementController.keepMomentum(duration: number)
	Motor.hold(motor, Clock.now(), duration)
end

function MovementController.setVerticalSpeed(speed: number)
	local body = Me.body
	if body == nil then
		return
	end
	local v = body.root.AssemblyLinearVelocity
	body.root.AssemblyLinearVelocity = Vector3.new(v.X, speed * Clock.scale(), v.Z)
end

function MovementController.knockback(velocity: Vector3, lock: number)
	local body = Me.body
	if body == nil then
		return
	end
	Motor.impulse(motor, velocity, Clock.now(), lock, "knockback")
	if velocity.Y > 0 then
		body.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		MovementController.setVerticalSpeed(velocity.Y)
	end
end

function MovementController.stop()
	Motor.stop(motor)
end

function MovementController.setVelocity(velocity: Vector3)
	motor.velocity = planar(velocity)
end

-- Input handlers ---------------------------------------------------------------------------

function MovementController.onJump()
	jumpPressedAt = Clock.now()
end

function MovementController.onShift(down: boolean)
	shiftHeld = down
	if not down then
		return
	end
	local body = Me.body
	if body == nil or external then
		return
	end
	local now = Clock.now()
	local state = Me.state()
	if not (state == "Free" or state == "Blocking") or now < dodgeReadyAt then
		return -- no dodge available: holding Shift just sprints
	end
	local grounded = MovementController.isGrounded()
	local dodge = dodgeDef()
	if not grounded and airDodgesUsed >= dodge.AirDodges then
		return
	end
	local direction = MovementController.inputDirection()
	if direction.Magnitude < 1e-3 then
		direction = facing
	end
	Motor.impulse(motor, direction * dodge.Speed, now, dodge.Duration, "dodge")
	dodgeUntil = now + dodge.Duration
	dodgeReadyAt = now + dodge.Cooldown
	if not grounded then
		airDodgesUsed += 1
	end
	facing = direction
	Events.send("Dodge", { dir = direction })
end

-- Per-frame --------------------------------------------------------------------------------

local function detectWall(root: BasePart): Vector3?
	local arena = workspace:FindFirstChild("Arena")
	if arena == nil then
		return nil
	end
	wallParams.FilterDescendantsInstances = { arena }
	local best: RaycastResult? = nil
	for _, direction in WALL_DIRECTIONS do
		for _, height in { 0, -1.5 } do
			local result = workspace:Raycast(
				root.Position + Vector3.new(0, height, 0),
				direction * M.WallDetectDistance,
				wallParams
			)
			if result and math.abs(result.Normal.Y) < M.WallMaxNormalY then
				if best == nil or result.Distance < best.Distance then
					best = result
				end
			end
		end
	end
	return if best then planar(best.Normal).Unit else nil
end

local function jumpVelocity(height: number): number
	return math.sqrt(2 * workspace.Gravity * height)
end

local function tryJump(body: Me.Body, now: number, grounded: boolean, state: string, moveMult: number)
	if now - jumpPressedAt > M.JumpBuffer then
		return
	end
	if not FREE_STATES[state] or moveMult <= 0 then
		return
	end
	local root = body.root
	local v = root.AssemblyLinearVelocity
	if grounded or now - lastGroundedAt <= M.CoyoteTime then
		jumpPressedAt = -math.huge
		lastGroundedAt = -math.huge
		body.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		root.AssemblyLinearVelocity = Vector3.new(v.X, jumpVelocity(body.stats.jumpHeight), v.Z)
	elseif wallNormal then
		jumpPressedAt = -math.huge
		local normal = wallNormal :: Vector3
		root.AssemblyLinearVelocity = Vector3.new(v.X, jumpVelocity(M.WallJumpHeight), v.Z)
		Motor.impulse(motor, normal * M.WallJumpPush, now, M.WallJumpLockout, "dodge")
		facing = normal
	elseif airJumpsUsed < body.def.movement.airJumps then
		jumpPressedAt = -math.huge
		airJumpsUsed += 1
		root.AssemblyLinearVelocity = Vector3.new(v.X, jumpVelocity(body.stats.jumpHeight), v.Z)
	end
end

local function updateFacing(body: Me.Body, dt: number, state: string, velocity: Vector3)
	local desired: Vector3? = nil
	local free = FREE_STATES[state] == true
	local holdingAction = not free and actionFacing ~= nil
	-- Blocks and parries face where you're looking; so does everything while locked on
	-- (except an attack that's already committed to a direction).
	local faceAim = state == "Blocking"
		or state == "Blockstun"
		or state == "Parrying"
		or state == "Countering"
		or (CameraController.lockTarget() ~= nil and not holdingAction)
	if faceAim then
		desired = CameraController.flatAim()
	elseif holdingAction then
		desired = actionFacing
	elseif velocity.Magnitude > 1 then
		desired = velocity.Unit
	end
	if FREE_STATES[state] then
		actionFacing = nil
	end
	if desired then
		local target = desired :: Vector3
		local turned = Motor.rotateToward(facing, target, math.rad(M.FacingTurnRateDeg) * dt)
		facing = turned
	end
	body.align.CFrame = CFrame.lookAlong(Vector3.zero, facing)
end

local function step(realDt: number)
	local body = Me.body
	local currentParams = params
	if body == nil or currentParams == nil then
		return
	end
	local scale = Clock.scale()
	if scale <= 0 then
		return
	end
	local t = Clock.now()
	local dt = realDt * scale
	local humanoid = body.humanoid
	local root = body.root
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	if grounded then
		lastGroundedAt = t
		airJumpsUsed = 0
		airDodgesUsed = 0
	end

	if external then
		local run = externalStep
		if run then
			run(dt, t)
		end
		return
	end

	local state = Me.state()
	local moveMult = Me.number(Attr.MoveMult, 1)
	local direction = MovementController.inputDirection()
	local canMove = moveMult > 0

	sprinting = shiftHeld and canMove and direction.Magnitude > 0 and FREE_STATES[state] == true and t >= dodgeUntil
	local target = if sprinting then body.stats.sprintSpeed else body.stats.walkSpeed
	target *= moveMult
	if not canMove then
		direction = Vector3.zero
		target = 0
	end

	local velocity =
		Motor.step(motor, dt, t, { direction = direction, targetSpeed = target, grounded = grounded }, currentParams)

	-- Wall slide
	wallNormal = if grounded then nil else detectWall(root)
	if wallNormal then
		local v = root.AssemblyLinearVelocity
		local maxFall = -M.WallSlideSpeed * scale
		if v.Y < maxFall then
			root.AssemblyLinearVelocity = Vector3.new(v.X, maxFall, v.Z)
		end
	end

	tryJump(body, t, grounded, state, moveMult)

	local speed = velocity.Magnitude
	humanoid.WalkSpeed = speed * scale
	humanoid:Move(if speed > 0.05 then velocity.Unit else Vector3.zero, false)
	updateFacing(body, dt, state, velocity)

	CameraController.setSprinting(sprinting and speed > body.stats.walkSpeed)
	if sprinting ~= lastReportedSprint then
		lastReportedSprint = sprinting
		Events.send("Sprint", { on = sprinting })
	end
	local airborne = not grounded
	if airborne ~= lastReportedAir then
		lastReportedAir = airborne
		Events.send("Airborne", { on = airborne })
	end
end

local function afterPhysics(realDt: number)
	local body = Me.body
	local currentParams = params
	if body == nil or currentParams == nil or external then
		return
	end
	local scale = Clock.scale()
	if scale <= 0 then
		return
	end
	Motor.reconcile(motor, body.root.AssemblyLinearVelocity / scale, realDt * scale, Clock.now(), currentParams)
	if body.root.Position.Y < M.KillPlaneY then
		Motor.stop(motor)
	end
end

-- Slow motion: rescale physics velocities; pause: freeze the character in place.
local function onScaleChanged(newScale: number, oldScale: number)
	local body = Me.body
	if body == nil then
		return
	end
	local root = body.root
	if newScale == 0 then
		pausedVelocity = root.AssemblyLinearVelocity / math.max(oldScale, 1e-3)
		root.Anchored = true
	elseif oldScale == 0 then
		root.Anchored = false
		root.AssemblyLinearVelocity = (pausedVelocity or Vector3.zero) * newScale
		pausedVelocity = nil
	else
		root.AssemblyLinearVelocity *= newScale / oldScale
	end
end

function MovementController.init()
	local player = Players.LocalPlayer
	task.spawn(function()
		-- Replace the default WASD/jump controls with ours.
		local playerModule =
			require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
		playerModule:GetControls():Disable()
	end)

	Me.Spawned:Connect(function(body)
		params = MotorParams.fromStats(body.stats)
		motor = Motor.new()
		facing = unitOr(planar(body.root.CFrame.LookVector), Vector3.new(0, 0, -1))
		actionFacing = nil
		external = false
		externalStep = nil
		dodgeReadyAt = -math.huge
		body.humanoid.AutoRotate = false
		if Clock.isPaused() then
			body.root.Anchored = true
		end
	end)

	Events.on("Knockback", function(payload)
		if typeof(payload.velocity) == "Vector3" then
			MovementController.knockback(payload.velocity, tonumber(payload.lock) or GameConfig.Combat.KnockbackLock)
		end
	end)
	Events.on("StopMotion", function()
		MovementController.stop()
	end)
	Events.on("DodgeRejected", function()
		Motor.clearLock(motor)
		dodgeUntil = -math.huge
	end)

	Clock.ScaleChanged:Connect(onScaleChanged)
	RunService:BindToRenderStep("DC_Movement", Enum.RenderPriority.Input.Value + 1, step)
	RunService.PostSimulation:Connect(afterPhysics)
end

return MovementController
