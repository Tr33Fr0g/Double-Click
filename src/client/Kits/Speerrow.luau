--!strict
-- Speerrow on the client. Rush (Q) is flown here because the client owns the character's
-- physics:
--   * Launches like a bullet toward wherever you're looking.
--   * Bounces off enemies, teammates, the ground, trees and walls. After each bounce he
--     lands briefly (can't be hit), then launches toward where the camera now looks.
--   * Travelling ~2.5 character-lengths without a bounce loses speed and ends Rush.
--   * Tap Q mid-flight to pull back.
-- The server validates every hit and handles blocks (bounce back + 0.6s stun).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Attr = require(Shared.Util.Attr)
local Clock = require(Shared.Util.Clock)
local SpeerrowKit = require(Shared.Characters.SpeerrowKit)
local Teams = require(Shared.Util.Teams)

local CameraController = require(script.Parent.Parent.CameraController)
local Effects = require(script.Parent.Parent.Effects)
local Events = require(script.Parent.Parent.Events)
local Me = require(script.Parent.Parent.Me)
local MovementController = require(script.Parent.Parent.MovementController)

local R = SpeerrowKit.Rush

type Phase = "Flying" | "Landing" | "Ending" | "PullBack"

type RushState = {
	phase: Phase,
	direction: Vector3,
	speed: number,
	startedAt: number,
	phaseUntil: number,
	sinceBounce: number,
	bounces: number,
	landNormal: Vector3,
	lastModel: Model?,
	lastModelAt: number,
	velocity: LinearVelocity,
	confirmed: boolean,
}

local Speerrow = {}

local rush: RushState? = nil
local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Include
local characterParams = OverlapParams.new()
characterParams.FilterType = Enum.RaycastFilterType.Include

local function stackSpeedMult(): number
	local stacks = Me.number(Attr.Stacks, 0)
	local halves = math.floor(stacks * 2 + 1e-9)
	return 1 + SpeerrowKit.Stacks.RushSpeedPerHalfStack * halves
end

local function freeFlight(): number
	return R.FreeFlightLengths * R.CharacterLength
end

local function finish(sendEnd: boolean, carry: Vector3?)
	local current = rush
	if current == nil then
		return
	end
	rush = nil
	current.velocity:Destroy()
	MovementController.setExternal(false)
	local body = Me.body
	if body then
		body.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		MovementController.setVelocity(
			carry or Vector3.new(current.direction.X, 0, current.direction.Z) * body.stats.walkSpeed
		)
	end
	if sendEnd then
		Events.send("Kit", { message = "RushEnd" })
	end
end

local function launch(state: RushState, direction: Vector3)
	state.phase = "Flying"
	state.direction = direction.Unit
	state.sinceBounce = 0
	-- Rush gets +5% speed per half stack.
	state.speed = R.Speed * stackSpeedMult()
	MovementController.setFacing(state.direction)
	Events.send("Kit", { message = "RushLaunch" })
end

local function land(state: RushState, position: Vector3?, normal: Vector3, now: number)
	local body = Me.body
	state.bounces += 1
	if state.bounces > R.MaxBounces or now - state.startedAt > R.MaxDuration then
		finish(true)
		return
	end
	state.phase = "Landing"
	state.phaseUntil = now + R.LandTime
	state.landNormal = normal
	state.velocity.VectorVelocity = Vector3.zero
	if body and position then
		body.root.CFrame = CFrame.new(position) * body.root.CFrame.Rotation
	end
	Events.send("Kit", { message = "RushLand" })
	Effects.puff(if body then body.root.Position else Vector3.zero)
end

local function otherHurtboxes(): { Instance }
	local body = Me.body
	local list: { Instance } = {}
	for _, instance in CollectionService:GetTagged(Attr.Tag) do
		if instance ~= (body and body.character) and instance:GetAttribute(Attr.State) ~= "Downed" then
			local hurtbox = instance:FindFirstChild("DC_Hurtbox")
			if hurtbox then
				table.insert(list, hurtbox)
			end
		end
	end
	return list
end

local function step(dt: number, now: number)
	local state = rush
	local body = Me.body
	if state == nil or body == nil then
		return
	end
	local scale = Clock.scale()
	local root = body.root

	-- Knocked out of the Rush by the server (hit, stunned, parried...). The server's
	-- state takes a moment to arrive, so only trust it once it has said "Rushing".
	local serverState = Me.state()
	if serverState == "Rushing" then
		state.confirmed = true
	elseif state.confirmed or now - state.startedAt > 1.5 then
		finish(false)
		return
	end

	if state.phase == "Landing" then
		state.velocity.VectorVelocity = Vector3.zero
		if now >= state.phaseUntil then
			-- Launch toward wherever the camera looks now, but never back into the
			-- surface he just landed on.
			local direction = CameraController.aim()
			local normal = state.landNormal
			local into = direction:Dot(normal)
			if into < 0.15 then
				direction = direction - normal * (into - 0.15)
			end
			launch(state, if direction.Magnitude > 1e-3 then direction else normal)
		end
		return
	end

	if state.phase == "PullBack" then
		state.velocity.VectorVelocity = -state.direction * R.PullBackSpeed * scale
		if now >= state.phaseUntil then
			finish(true, Vector3.zero)
		end
		return
	end

	if state.phase == "Ending" then
		-- Out of speed: bleed it off, then hand control back.
		state.speed = math.max(0, state.speed - R.Speed * 4 * dt)
		state.velocity.VectorVelocity = state.direction * state.speed * scale
		if state.speed <= body.stats.walkSpeed then
			finish(true)
		end
		return
	end

	-- Flying: bounce off characters first.
	characterParams.FilterDescendantsInstances = otherHurtboxes()
	for _, part in workspace:GetPartBoundsInRadius(root.Position, R.HitRadius, characterParams) do
		local model = part.Parent
		if model and model:IsA("Model") and not (model == state.lastModel and now - state.lastModelAt < 0.3) then
			local targetRoot = model:FindFirstChild("HumanoidRootPart")
			local away = if targetRoot and targetRoot:IsA("BasePart")
				then Vector3.new(root.Position.X - targetRoot.Position.X, 0, root.Position.Z - targetRoot.Position.Z)
				else -state.direction
			local normal = if away.Magnitude > 1e-3 then away.Unit else -state.direction
			if Teams.areEnemies(body.character, model) then
				Events.send("Kit", { message = "RushHit", target = model })
			end
			state.lastModel = model
			state.lastModelAt = now
			land(state, nil, normal, now)
			return
		end
	end

	-- Then the map (ground, trees, walls, rocks).
	local distance = state.speed * dt
	local arena = workspace:FindFirstChild("Arena")
	if arena then
		surfaceParams.FilterDescendantsInstances = { arena }
		local hit =
			workspace:Spherecast(root.Position, R.SurfaceRadius, state.direction * (distance + 0.3), surfaceParams)
		if hit then
			land(state, hit.Position + hit.Normal * (R.SurfaceRadius + 0.3), hit.Normal, now)
			return
		end
	end

	state.sinceBounce += distance
	if state.sinceBounce > freeFlight() or now - state.startedAt > R.MaxDuration then
		state.phase = "Ending"
	end
	state.velocity.VectorVelocity = state.direction * state.speed * scale
end

-- Called by CombatController before an ability request is sent. Returns false to
-- swallow the input (e.g. Q mid-flight pulls back instead of starting a new Rush).
function Speerrow.onAbility(slot: string, aim: Vector3): boolean
	local body = Me.body
	if body == nil then
		return false
	end
	local now = Clock.now()
	if slot == "Q" then
		local current = rush
		if current then
			if current.phase == "Flying" or current.phase == "Landing" then
				current.phase = "PullBack"
				current.phaseUntil = now + R.PullBackTime
			end
			return false
		end
		local state = Me.state()
		if not (state == "Free" or state == "Blocking") or Me.cooldownLeft("Q", now) > 0 then
			-- Not available here; don't ask the server (it would wait for a flight that
			-- never starts).
			return false
		end
		local velocity = Instance.new("LinearVelocity")
		velocity.Name = "DC_Rush"
		velocity.Attachment0 = body.attachment
		velocity.RelativeTo = Enum.ActuatorRelativeTo.World
		velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		velocity.MaxForce = math.huge
		velocity.VectorVelocity = Vector3.zero
		velocity.Parent = body.root
		body.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		local newRush: RushState = {
			phase = "Flying",
			direction = aim,
			speed = R.Speed,
			startedAt = now,
			phaseUntil = 0,
			sinceBounce = 0,
			bounces = 0,
			landNormal = Vector3.yAxis,
			lastModel = nil,
			lastModelAt = -math.huge,
			velocity = velocity,
			confirmed = false,
		}
		rush = newRush
		MovementController.setExternal(true, step)
		launch(newRush, if aim.Magnitude > 1e-3 then aim else body.root.CFrame.LookVector)
		return true
	elseif slot == "R" then
		MovementController.faceAction(aim)
		MovementController.lunge(aim, SpeerrowKit.Zap.lunge or 0)
	elseif slot == "E" or slot == "G" then
		MovementController.faceAction(aim)
	end
	return true
end

function Speerrow.isRushing(): boolean
	return rush ~= nil
end

function Speerrow.init()
	Events.on("AbilityRejected", function(payload)
		if payload.slot == "Q" then
			finish(false)
		end
	end)
	Events.on("RushBlocked", function(payload)
		local away = if typeof(payload.away) == "Vector3" then payload.away :: Vector3 else Vector3.zero
		finish(false, Vector3.zero)
		MovementController.knockback(away * 30 + Vector3.new(0, 18, 0), 0.25)
	end)
	Events.on("RushEnd", function()
		finish(false)
	end)
	Me.Despawned:Connect(function()
		local current = rush
		if current then
			rush = nil
			current.velocity:Destroy()
			MovementController.setExternal(false)
		end
	end)
end

return Speerrow
