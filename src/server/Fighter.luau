--!strict
-- Server-side combat state for one character (player or dummy), plus the registry of all
-- fighters. The server is authoritative for HP, states, cooldowns, stacks and ult; it
-- mirrors them onto model attributes so clients can read them.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Attr = require(Shared.Util.Attr)
local BlockMeter = require(Shared.Combat.BlockMeter)
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Util.Signal)
local Stacks = require(Shared.Combat.Stacks)
local Stats = require(Shared.Combat.Stats)
local StunChain = require(Shared.Combat.StunChain)
local Types = require(Shared.Types)

local Combat = GameConfig.Combat

export type State =
	"Free"
	| "Attacking"
	| "Blocking"
	| "Blockstun"
	| "Hitstun"
	| "Stunned"
	| "Recovery"
	| "Parrying"
	| "Countering"
	| "Rushing"
	| "Dodging"
	| "Downed"

export type ActionState = {
	move: Types.MoveDef,
	slot: string,
	phase: Types.Phase,
	phaseStart: number,
	phaseEnd: number,
	speed: number, -- attack speed multiplier (phases are divided by it)
	aim: Vector3, -- flat aim (hitboxes and facing)
	aim3: Vector3, -- full aim, including up/down (projectiles)
	hit: { [Model]: boolean },
	spawned: boolean, -- projectile already fired
	activeChecks: number,
	extraRecovery: number,
	isStringHit: boolean,
	isStringEnd: boolean,
}

export type HitContext = {
	projectile: boolean?,
	direction: Vector3?, -- travel direction of the attack (projectiles, area pushes)
	origin: Vector3?, -- where the attack came from (hitbox center)
	time: number?, -- impact time; defaults to now
}

export type Kit = {
	damageBonus: ((fighter: Fighter, move: Types.MoveDef) -> number)?,
	onDamaged: ((fighter: Fighter) -> ())?,
	onParry: ((fighter: Fighter, attacker: Fighter, move: Types.MoveDef, timing: number, ctx: HitContext) -> ())?,
	onFullCounter: ((fighter: Fighter, attacker: Fighter, move: Types.MoveDef, timing: number, ctx: HitContext) -> ())?,
	ability: ((fighter: Fighter, slot: string, payload: { [string]: any }, now: number) -> ())?,
	message: ((fighter: Fighter, name: string, payload: { [string]: any }, now: number) -> ())?,
	update: ((fighter: Fighter, now: number, dt: number) -> ())?,
	reset: ((fighter: Fighter) -> ())?,
}

export type Fighter = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	hurtbox: BasePart,
	attachment: Attachment,
	align: AlignOrientation,
	player: Player?,
	def: Types.CharacterDef,
	stats: Stats.Derived,
	isDummy: boolean,

	hp: number,
	ult: number,
	block: BlockMeter.State,
	stun: StunChain.State,
	stacks: Stacks.State,

	state: State,
	stateUntil: number,
	pose: string?, -- pose override for the current state

	blockHeld: boolean,
	blockStart: number?, -- when the current block's close-block timer started
	blockPressAt: number, -- when F was last pressed (-inf if that press can't close block)
	blockReleasedAt: number,
	parryStart: number?,
	counterStart: number?,

	action: ActionState?,
	buffered: { variant: string, aim: Vector3, at: number }?,
	m1Index: number,
	m1LastEnd: number,
	m1LockUntil: number,
	cooldowns: { [string]: number },

	intangible: boolean,
	hyperArmor: boolean,
	sprinting: boolean,
	airborne: boolean,

	knockbackUntil: number,
	knockbackDir: Vector3,
	wallStunned: boolean,

	kit: Kit?,
	kitState: { [string]: any },
	stackDuration: number,
	lastAttacker: Fighter?,

	-- Hooks set by whoever drives this fighter's body (player client or dummy AI).
	applyKnockback: (velocity: Vector3, lock: number) -> (),
	stopMotion: () -> (),

	attrCache: { [string]: any },
	destroyed: boolean,
}

local Fighter = {}

Fighter.all = {} :: { Fighter }
Fighter.byModel = {} :: { [Model]: Fighter }
Fighter.byHurtbox = {} :: { [BasePart]: Fighter }
Fighter.Added = Signal.new() :: Signal.Signal<Fighter>
Fighter.Removed = Signal.new() :: Signal.Signal<Fighter>

local overlapParams: OverlapParams? = nil

local HURTBOX_SIZE = Vector3.new(3.6, 5.4, 2.4)
local HURTBOX_OFFSET = CFrame.new(0, -0.35, 0)

local function noop() end

local function invalidateQueries()
	overlapParams = nil
end

function Fighter.overlapParams(): OverlapParams
	local params = overlapParams
	if params then
		return params
	end
	local newParams = OverlapParams.new()
	newParams.FilterType = Enum.RaycastFilterType.Include
	local list: { Instance } = {}
	for hurtbox in Fighter.byHurtbox do
		table.insert(list, hurtbox)
	end
	newParams.FilterDescendantsInstances = list
	overlapParams = newParams
	return newParams
end

function Fighter.hurtboxes(): { BasePart }
	local list = {}
	for hurtbox in Fighter.byHurtbox do
		table.insert(list, hurtbox)
	end
	return list
end

function Fighter.get(model: Instance?): Fighter?
	if model == nil or not model:IsA("Model") then
		return nil
	end
	return Fighter.byModel[model :: Model]
end

function Fighter.fromPart(part: Instance): Fighter?
	local byHurtbox = if part:IsA("BasePart") then Fighter.byHurtbox[part] else nil
	if byHurtbox then
		return byHurtbox
	end
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local found = Fighter.byModel[model]
		if found then
			return found
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function Fighter.new(model: Model, def: Types.CharacterDef, player: Player?, team: string): Fighter
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	assert(humanoid and root, "Fighter needs a Humanoid and a HumanoidRootPart")

	local stats = Stats.derive(def.stats, GameConfig.Stats, GameConfig.HealthByStat, def.movement.sprintSpeedOverride)

	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = false
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = stats.jumpHeight
	humanoid.WalkSpeed = stats.walkSpeed

	local hurtbox = Instance.new("Part")
	hurtbox.Name = "DC_Hurtbox"
	hurtbox.Size = HURTBOX_SIZE
	hurtbox.Transparency = 1
	hurtbox.CanCollide = false
	hurtbox.CanTouch = false
	hurtbox.CanQuery = true
	hurtbox.Massless = true
	hurtbox.CastShadow = false
	hurtbox.CFrame = root.CFrame * HURTBOX_OFFSET
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = hurtbox
	weld.Parent = hurtbox
	hurtbox.Parent = model

	local attachment = Instance.new("Attachment")
	attachment.Name = "DC_Attachment"
	attachment.Parent = root

	-- Facing is driven by an AlignOrientation (the owner of the body sets its CFrame).
	local align = Instance.new("AlignOrientation")
	align.Name = "DC_Align"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	align.CFrame = CFrame.lookAlong(Vector3.zero, if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1))
	align.Parent = root

	local self: Fighter = {
		model = model,
		humanoid = humanoid,
		root = root,
		hurtbox = hurtbox,
		attachment = attachment,
		align = align,
		player = player,
		def = def,
		stats = stats,
		isDummy = player == nil,

		hp = stats.maxHp,
		ult = 0,
		block = BlockMeter.new(stats.blockMeterMax),
		stun = StunChain.new(),
		stacks = Stacks.new(),

		state = "Free",
		stateUntil = 0,
		pose = nil,

		blockHeld = false,
		blockStart = nil,
		blockPressAt = -math.huge,
		blockReleasedAt = -math.huge,
		parryStart = nil,
		counterStart = nil,

		action = nil,
		buffered = nil,
		m1Index = 1,
		m1LastEnd = -math.huge,
		m1LockUntil = -math.huge,
		cooldowns = {},

		intangible = false,
		hyperArmor = false,
		sprinting = false,
		airborne = false,

		knockbackUntil = -math.huge,
		knockbackDir = Vector3.zero,
		wallStunned = false,

		kit = nil,
		kitState = {},
		stackDuration = 10,
		lastAttacker = nil,

		applyKnockback = noop :: any,
		stopMotion = noop,

		attrCache = {},
		destroyed = false,
	}

	model:SetAttribute(Attr.Character, def.id)
	model:SetAttribute(Attr.Team, team)
	CollectionService:AddTag(model, Attr.Tag)

	table.insert(Fighter.all, self)
	Fighter.byModel[model] = self
	Fighter.byHurtbox[hurtbox] = self
	invalidateQueries()
	Fighter.sync(self, 0)
	Fighter.Added:Fire(self)
	return self
end

function Fighter.destroy(self: Fighter)
	if self.destroyed then
		return
	end
	self.destroyed = true
	local index = table.find(Fighter.all, self)
	if index then
		table.remove(Fighter.all, index)
	end
	Fighter.byModel[self.model] = nil
	Fighter.byHurtbox[self.hurtbox] = nil
	invalidateQueries()
	Fighter.Removed:Fire(self)
end

-- Attributes -------------------------------------------------------------------------

local function setAttr(self: Fighter, name: string, value: any)
	if self.attrCache[name] ~= value then
		self.attrCache[name] = value
		self.model:SetAttribute(name, value)
	end
end

Fighter.setAttr = setAttr

local function round(value: number, step: number): number
	return math.floor(value / step + 0.5) * step
end

-- How much the fighter may move in its current state (read by the client's movement).
function Fighter.moveMult(self: Fighter): number
	local state = self.state
	if state == "Free" or state == "Dodging" or state == "Rushing" then
		return 1
	elseif state == "Blocking" then
		return GameConfig.Movement.BlockMoveMult
	elseif state == "Blockstun" or state == "Recovery" then
		return 0.2
	elseif state == "Attacking" then
		local action = self.action
		if action then
			local mult = action.move.moveMult
			if mult then
				if action.phase == "Windup" then
					return mult.Windup
				elseif action.phase == "Active" then
					return mult.Active
				end
				return mult.Recovery
			end
			return if action.phase == "Recovery" then 0.5 else 0.3
		end
		return 0.3
	elseif state == "Parrying" then
		return 0.5
	end
	return 0
end

function Fighter.sync(self: Fighter, now: number)
	setAttr(self, Attr.HP, round(self.hp, 0.1))
	setAttr(self, Attr.MaxHP, self.stats.maxHp)
	setAttr(self, Attr.BlockMeter, round(self.block.value, 0.5))
	setAttr(self, Attr.BlockMeterMax, self.block.max)
	setAttr(self, Attr.Ult, round(self.ult, 0.1))
	setAttr(self, Attr.State, self.state)
	setAttr(self, Attr.StateUntil, self.stateUntil)
	setAttr(self, Attr.MoveMult, Fighter.moveMult(self))
	setAttr(self, Attr.Blocking, self.state == "Blocking" or self.state == "Blockstun")
	setAttr(self, Attr.Intangible, self.intangible)
	setAttr(self, Attr.Stacks, self.stacks.value)
	setAttr(self, Attr.StacksExpireAt, if self.stacks.value > 0 then self.stacks.lastGainAt + self.stackDuration else 0)
	local count, immuneLeft = StunChain.peek(self.stun, now, Combat.Stun)
	setAttr(self, Attr.StunCount, count)
	setAttr(self, Attr.StunImmuneUntil, if immuneLeft > 0 then now + immuneLeft else 0)

	local action = self.action
	if action then
		setAttr(self, Attr.Action, action.move.name)
		setAttr(self, Attr.Pose, action.move.pose)
		setAttr(self, Attr.Phase, action.phase)
		setAttr(self, Attr.PhaseStart, action.phaseStart)
		setAttr(self, Attr.PhaseEnd, action.phaseEnd)
	else
		setAttr(self, Attr.Action, "")
		setAttr(self, Attr.Pose, self.pose or "")
		setAttr(self, Attr.Phase, "")
	end

	for slot, readyAt in self.cooldowns do
		setAttr(self, Attr.cooldown(slot), readyAt)
	end
end

-- State --------------------------------------------------------------------------------

function Fighter.isBlocking(self: Fighter): boolean
	return self.state == "Blocking" or self.state == "Blockstun"
end

-- Free to start an attack or ability.
function Fighter.canAct(self: Fighter): boolean
	return self.action == nil and (self.state == "Free" or self.state == "Blocking")
end

function Fighter.setState(self: Fighter, state: State, duration: number?, now: number?, pose: string?)
	self.state = state
	self.stateUntil = if duration and now then now + duration else 0
	self.pose = pose
end

-- Called when a timed state runs out: back to blocking if F is still held, else free.
-- A block that comes back on by itself keeps its original press time, so holding F
-- through a string (or through hitstun) never turns into a free close block.
function Fighter.release(self: Fighter, _now: number)
	self.pose = nil
	self.stateUntil = 0
	if self.blockHeld then
		self.state = "Blocking"
		self.blockStart = self.blockStart or self.blockPressAt
	else
		self.state = "Free"
		self.blockStart = nil
	end
end

-- When a button was pressed, from the client's timestamp: never in the future and never
-- further back than the lag compensation allows.
function Fighter.pressTime(t: any, now: number): number
	if type(t) ~= "number" or t ~= t then
		return now
	end
	return math.clamp(t, now - Combat.LagCompensationMax, now)
end

function Fighter.cancelAction(self: Fighter)
	self.action = nil
	self.buffered = nil
end

function Fighter.cooldownReady(self: Fighter, slot: string, now: number): boolean
	local readyAt = self.cooldowns[slot]
	return readyAt == nil or now >= readyAt
end

function Fighter.setCooldown(self: Fighter, slot: string, readyAt: number)
	self.cooldowns[slot] = readyAt
end

function Fighter.addUlt(self: Fighter, amount: number)
	self.ult = math.clamp(self.ult + amount, 0, Combat.UltMax)
end

-- Horizontal speed in game units (world velocity divided by the slow-motion scale).
function Fighter.planarSpeed(self: Fighter, timeScale: number): number
	if timeScale <= 0 then
		return 0
	end
	local v = self.root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude / timeScale
end

function Fighter.facing(self: Fighter): Vector3
	local look = self.root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
end

-- Puts everything back to the start-of-round state (HP, cooldowns, ult, stacks...).
function Fighter.resetCombat(self: Fighter)
	self.hp = self.stats.maxHp
	self.ult = 0
	BlockMeter.refill(self.block)
	StunChain.reset(self.stun)
	Stacks.reset(self.stacks)
	self.state = "Free"
	self.stateUntil = 0
	self.pose = nil
	self.blockStart = nil
	self.parryStart = nil
	self.counterStart = nil
	self.action = nil
	self.buffered = nil
	self.m1Index = 1
	self.m1LockUntil = -math.huge
	self.intangible = false
	self.hyperArmor = false
	self.knockbackUntil = -math.huge
	self.wallStunned = false
	for slot in self.cooldowns do
		self.cooldowns[slot] = 0
	end
	local kit = self.kit
	if kit and kit.reset then
		kit.reset(self)
	end
end

-- Timers that don't depend on combat resolution: state expiry, block meter, stacks.
function Fighter.update(self: Fighter, now: number, dt: number)
	local state = self.state
	if self.stateUntil > 0 and now >= self.stateUntil then
		if state == "Downed" then
			Fighter.resetCombat(self)
		elseif
			state == "Hitstun"
			or state == "Stunned"
			or state == "Blockstun"
			or state == "Recovery"
			or state == "Dodging"
		then
			Fighter.release(self, now)
		end
	end

	-- F held while free (e.g. pressed again right after letting go): start blocking once
	-- the re-press delay is over.
	if
		self.state == "Free"
		and self.blockHeld
		and self.action == nil
		and now - self.blockReleasedAt >= Combat.BlockRepressDelay
	then
		self.state = "Blocking"
		self.blockStart = self.blockPressAt
	end

	BlockMeter.update(self.block, dt, now, Fighter.isBlocking(self), Combat)
end

return Fighter
