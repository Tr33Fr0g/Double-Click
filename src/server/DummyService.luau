--!strict
-- Training dummies with configurable attacks and timings, for practicing blocks, close
-- blocks, parries and Full Counters (doc: "Training dummy"). Configured from the debug
-- panel; the config is shared by every dummy on the server.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Characters)
local Clock = require(Shared.Util.Clock)
local DummyAttacks = require(Shared.Config.DummyAttacks)
local Motor = require(Shared.Movement.Motor)
local MotorParams = require(Shared.Movement.MotorParams)
local Teams = require(Shared.Util.Teams)
local Types = require(Shared.Types)

local Actions = require(script.Parent.Actions)
local DebugService = require(script.Parent.DebugService)
local Fighter = require(script.Parent.Fighter)

type Fighter = Fighter.Fighter

type DummyState = {
	fighter: Fighter,
	motor: Motor.State,
	params: Motor.Params,
	facing: Vector3,
	nextAttackAt: number,
	sequence: { string },
	sequenceIndex: number,
	pausedVelocity: Vector3?,
}

local BEHAVIORS: { string } = { "Idle", "Attack", "Block", "Block + Attack" }
local ATTACK_RANGE = 70 -- the dummy turns to face players within this range
local REFILL_DELAY = 3

local DummyService = {}

local config = {
	behavior = "Attack" :: string,
	attack = "Jab",
	interval = 2,
	windup = nil :: number?, -- nil = the attack's own wind-up
	infiniteHp = true,
	faceTarget = true,
}

local dummies: { DummyState } = {}
local folder: Instance = workspace
local spawnPoints: { CFrame } = {}

local function publishConfig()
	ReplicatedStorage:SetAttribute(
		"DC_DummyConfig",
		HttpService:JSONEncode({
			behavior = config.behavior,
			attack = config.attack,
			interval = config.interval,
			windup = config.windup or DummyService.defaultWindup(),
			windupOverridden = config.windup ~= nil,
			infiniteHp = config.infiniteHp,
			count = #dummies,
		})
	)
end

function DummyService.defaultWindup(): number
	local sequence = DummyAttacks.Sequences[config.attack] or { config.attack }
	local move = DummyAttacks.Attacks[sequence[1]]
	return if move then move.windup else 0.3
end

-- Rig -------------------------------------------------------------------------------------

local function makePart(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeMotor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = part0
end

-- A classic R6 rig built from parts, so it works without loading any assets.
local function buildRig(cframe: CFrame, color: Color3): (Model, Humanoid)
	local model = Instance.new("Model")
	model.Name = "Training Dummy"

	local root = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), color, model)
	root.Transparency = 1
	root.CanCollide = false
	local torso = makePart("Torso", Vector3.new(2, 2, 1), color, model)
	local head = makePart("Head", Vector3.new(2, 1, 1), Color3.fromRGB(240, 220, 190), model)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local limbColor = color:Lerp(Color3.new(0, 0, 0), 0.25)
	local leftArm = makePart("Left Arm", Vector3.new(1, 2, 1), limbColor, model)
	local rightArm = makePart("Right Arm", Vector3.new(1, 2, 1), limbColor, model)
	local leftLeg = makePart("Left Leg", Vector3.new(1, 2, 1), limbColor, model)
	local rightLeg = makePart("Right Leg", Vector3.new(1, 2, 1), limbColor, model)
	for _, limb in { leftArm, rightArm, leftLeg, rightLeg } do
		limb.CanCollide = false
	end

	root.CFrame = cframe
	torso.CFrame = cframe
	head.CFrame = cframe * CFrame.new(0, 1.5, 0)
	leftArm.CFrame = cframe * CFrame.new(-1.5, 0, 0)
	rightArm.CFrame = cframe * CFrame.new(1.5, 0, 0)
	leftLeg.CFrame = cframe * CFrame.new(-0.5, -2, 0)
	rightLeg.CFrame = cframe * CFrame.new(0.5, -2, 0)

	-- Standard R6 joint offsets.
	makeMotor(
		"RootJoint",
		root,
		torso,
		CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	)
	makeMotor(
		"Neck",
		torso,
		head,
		CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	)
	makeMotor(
		"Right Shoulder",
		torso,
		rightArm,
		CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	)
	makeMotor(
		"Left Shoulder",
		torso,
		leftArm,
		CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
	)
	makeMotor(
		"Right Hip",
		torso,
		rightLeg,
		CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	)
	makeMotor(
		"Left Hip",
		torso,
		leftLeg,
		CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
	)

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = model
	model.PrimaryPart = root
	return model, humanoid
end

-- Spawning ----------------------------------------------------------------------------------

local function removeDummy(index: number)
	local state = dummies[index]
	table.remove(dummies, index)
	Fighter.destroy(state.fighter)
	state.fighter.model:Destroy()
end

function DummyService.spawn(cframe: CFrame): Fighter
	local def = Characters.get("Dummy")
	local model, _humanoid = buildRig(cframe + Vector3.new(0, 3, 0), def.color)
	model.Parent = folder
	local fighter = Fighter.new(model, def, nil, "Dummy")
	fighter.kitState.infiniteHp = config.infiniteHp
	fighter.root:SetNetworkOwner(nil)

	local state: DummyState = {
		fighter = fighter,
		motor = Motor.new(),
		params = MotorParams.fromStats(fighter.stats),
		facing = Fighter.facing(fighter),
		nextAttackAt = Clock.now() + config.interval,
		sequence = {},
		sequenceIndex = 0,
		pausedVelocity = nil,
	}

	fighter.applyKnockback = function(velocity: Vector3, lock: number)
		local scale = Clock.scale()
		Motor.impulse(state.motor, velocity, Clock.now(), lock, "knockback")
		if velocity.Y > 0 then
			fighter.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			local current = fighter.root.AssemblyLinearVelocity
			fighter.root.AssemblyLinearVelocity = Vector3.new(current.X, velocity.Y * scale, current.Z)
		end
	end
	fighter.stopMotion = function()
		Motor.stop(state.motor)
	end

	table.insert(dummies, state)
	publishConfig()
	return fighter
end

function DummyService.clear()
	for index = #dummies, 1, -1 do
		removeDummy(index)
	end
	publishConfig()
end

-- AI ------------------------------------------------------------------------------------------

local function nearestPlayerFighter(from: Fighter): Fighter?
	local best: Fighter? = nil
	local bestDistance = ATTACK_RANGE
	for _, other in Fighter.all do
		if other.player and other.state ~= "Downed" and Teams.areEnemies(from.model, other.model) then
			local distance = (other.root.Position - from.root.Position).Magnitude
			if distance < bestDistance then
				best = other
				bestDistance = distance
			end
		end
	end
	return best
end

local function moveFor(id: string): Types.MoveDef?
	local move = DummyAttacks.Attacks[id]
	if move and config.windup then
		local copy = table.clone(move)
		copy.windup = config.windup
		return copy
	end
	return move
end

local function wantsBlock(): boolean
	return config.behavior == "Block" or config.behavior == "Block + Attack"
end

local function wantsAttack(): boolean
	return config.behavior == "Attack" or config.behavior == "Block + Attack"
end

local function startNextInSequence(state: DummyState, target: Fighter?, now: number)
	local fighter = state.fighter
	state.sequenceIndex += 1
	local id = state.sequence[state.sequenceIndex]
	local move = if id then moveFor(id) else nil
	if move == nil then
		state.sequence = {}
		state.sequenceIndex = 0
		state.nextAttackAt = now + config.interval
		return
	end
	local aim = state.facing
	if target then
		aim = target.root.Position - fighter.root.Position
	end
	Actions.start(fighter, move, aim, now, "Dummy")
end

local function stepAI(state: DummyState, now: number)
	local fighter = state.fighter
	if fighter.state == "Downed" then
		return
	end

	fighter.blockHeld = wantsBlock()
	local current: string = fighter.state
	if fighter.blockHeld and current == "Free" then
		-- The dummy holds its block well before any hit: always a normal block.
		fighter.state = "Blocking"
		fighter.blockStart = now - 1
	elseif not fighter.blockHeld and current == "Blocking" then
		Fighter.release(fighter, now)
	elseif current == "Blocking" then
		local blockStart = fighter.blockStart
		if blockStart == nil or now - blockStart < 1 then
			fighter.blockStart = now - 1
		end
	end

	if fighter.kitState.infiniteHp and now - (fighter.kitState.lastDamagedAt or -math.huge) > REFILL_DELAY then
		fighter.hp = fighter.stats.maxHp
	end

	local target = nearestPlayerFighter(fighter)
	if config.faceTarget and target and fighter.action == nil then
		local offset = target.root.Position - fighter.root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude > 0.5 then
			state.facing = flat.Unit
		end
	end

	if not wantsAttack() then
		state.sequence = {}
		return
	end
	if fighter.action or not Fighter.canAct(fighter) then
		return
	end
	if state.sequenceIndex > 0 then
		startNextInSequence(state, target, now)
	elseif now >= state.nextAttackAt then
		state.sequence = DummyAttacks.Sequences[config.attack] or { config.attack }
		state.sequenceIndex = 0
		startNextInSequence(state, target, now)
	end
end

local function stepBody(state: DummyState, now: number, dt: number)
	local fighter = state.fighter
	local scale = Clock.scale()
	if scale <= 0 then
		return
	end
	local grounded = fighter.humanoid.FloorMaterial ~= Enum.Material.Air
	local velocity = Motor.step(state.motor, dt, now, {
		direction = Vector3.zero,
		targetSpeed = 0,
		grounded = grounded,
	}, state.params)
	local speed = velocity.Magnitude
	fighter.humanoid.WalkSpeed = speed * scale
	fighter.humanoid:Move(if speed > 0.05 then velocity.Unit else Vector3.zero, false)
	Motor.reconcile(state.motor, fighter.root.AssemblyLinearVelocity / scale, dt, now, state.params)

	local action = fighter.action
	local facing = if action then action.aim else state.facing
	fighter.align.CFrame = CFrame.lookAlong(Vector3.zero, facing)
end

function DummyService.step(now: number, dt: number)
	for index = #dummies, 1, -1 do
		local state = dummies[index]
		if state.fighter.model.Parent == nil then
			table.remove(dummies, index)
			Fighter.destroy(state.fighter)
			continue
		end
		stepAI(state, now)
		stepBody(state, now, dt)
		if state.fighter.root.Position.Y < -60 then
			state.fighter.root.CFrame = (spawnPoints[1] or CFrame.new(0, 10, 0)) + Vector3.new(0, 4, 0)
		end
	end
end

-- Debug commands --------------------------------------------------------------------------------

local function cycle<T>(list: { T }, current: T, value: any): T
	if value ~= nil then
		for _, item in list do
			if item == value then
				return item
			end
		end
	end
	local index = table.find(list, current) or 0
	return list[index % #list + 1]
end

local function registerCommands()
	DebugService.registerCommand("DummySpawn", function(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
			local position = root.Position + look * 8
			DummyService.spawn(CFrame.lookAt(position, position - look))
		end
	end)
	DebugService.registerCommand("DummyClear", function()
		DummyService.clear()
	end)
	DebugService.registerCommand("DummyReset", function()
		for _, state in dummies do
			Fighter.resetCombat(state.fighter)
			state.fighter.kitState.infiniteHp = config.infiniteHp
		end
	end)
	DebugService.registerCommand("DummyBehavior", function(_, args)
		config.behavior = cycle(BEHAVIORS, config.behavior, args.value)
		publishConfig()
	end)
	DebugService.registerCommand("DummyAttack", function(_, args)
		config.attack = cycle(DummyAttacks.Order, config.attack, args.value)
		config.windup = nil
		publishConfig()
	end)
	DebugService.registerCommand("DummyInterval", function(_, args)
		local delta = tonumber(args.delta) or 0
		config.interval = math.clamp(math.floor((config.interval + delta) * 10 + 0.5) / 10, 0.3, 8)
		publishConfig()
	end)
	DebugService.registerCommand("DummyWindup", function(_, args)
		if args.reset then
			config.windup = nil
		else
			local delta = tonumber(args.delta) or 0
			local current = config.windup or DummyService.defaultWindup()
			config.windup = math.clamp(math.floor((current + delta) * 100 + 0.5) / 100, 0.05, 2)
		end
		publishConfig()
	end)
	DebugService.registerCommand("DummyInfiniteHP", function()
		config.infiniteHp = not config.infiniteHp
		for _, state in dummies do
			state.fighter.kitState.infiniteHp = config.infiniteHp
		end
		publishConfig()
	end)
end

-- Freezes dummies while the clock is paused and rescales their velocity in slow motion.
local function onScaleChanged(newScale: number, oldScale: number)
	for _, state in dummies do
		local root = state.fighter.root
		if newScale == 0 then
			state.pausedVelocity = root.AssemblyLinearVelocity / math.max(oldScale, 1e-3)
			root.Anchored = true
		elseif oldScale == 0 then
			root.Anchored = false
			root:SetNetworkOwner(nil)
			root.AssemblyLinearVelocity = (state.pausedVelocity or Vector3.zero) * newScale
			state.pausedVelocity = nil
		else
			root.AssemblyLinearVelocity *= newScale / oldScale
		end
	end
end

function DummyService.init(dummyFolder: Instance, points: { CFrame })
	folder = dummyFolder
	spawnPoints = points
	registerCommands()
	Clock.ScaleChanged:Connect(onScaleChanged)
	for _, point in points do
		DummyService.spawn(point)
	end
	publishConfig()
	Players.PlayerAdded:Connect(function()
		publishConfig()
	end)
end

return DummyService
