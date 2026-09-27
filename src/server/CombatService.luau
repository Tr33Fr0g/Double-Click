--!strict
-- Turns players into fighters, validates their gameplay requests and runs the combat loop
-- on game time (so debug slow motion and frame step affect everything).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Characters = require(Shared.Characters)
local Clock = require(Shared.Util.Clock)
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)

local Actions = require(script.Parent.Actions)
local DummyService = require(script.Parent.DummyService)
local Fighter = require(script.Parent.Fighter)
local HitResolver = require(script.Parent.HitResolver)
local Kits = require(script.Parent.Kits)
local Projectiles = require(script.Parent.Projectiles)
local ServerNet = require(script.Parent.ServerNet)

type Fighter = Fighter.Fighter

local Combat = GameConfig.Combat
local Movement = GameConfig.Movement

local CombatService = {}

local spawnCFrame = CFrame.new(0, 3, 0)

local function isFiniteVector(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local v = value :: Vector3
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

local function aimFrom(payload: { [string]: any }, fighter: Fighter): Vector3
	if isFiniteVector(payload.aim) then
		local aim = payload.aim :: Vector3
		if aim.Magnitude > 1e-3 then
			return aim.Unit
		end
	end
	return Fighter.facing(fighter)
end

-- Players ---------------------------------------------------------------------------------

local function setupCharacter(player: Player, character: Model)
	local previous = Fighter.get(character)
	if previous then
		Fighter.destroy(previous)
	end
	character:WaitForChild("HumanoidRootPart")
	character:WaitForChild("Humanoid")

	local def = Characters.get(Characters.Default)
	local fighter = Fighter.new(character, def, player, player.Name)
	Kits.attach(fighter)
	fighter.cooldowns.Dodge = 0

	fighter.applyKnockback = function(velocity: Vector3, lock: number)
		ServerNet.toPlayer(player, "Knockback", { velocity = velocity, lock = lock })
	end
	fighter.stopMotion = function()
		ServerNet.toPlayer(player, "StopMotion", {})
	end

	local humanoid = fighter.humanoid
	humanoid.Died:Connect(function()
		Fighter.destroy(fighter)
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			Fighter.destroy(fighter)
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	if player.Character then
		task.spawn(setupCharacter, player, player.Character)
	end
end

-- Requests ----------------------------------------------------------------------------------

local function onBlockStart(fighter: Fighter, payload: { [string]: any }, now: number)
	fighter.blockHeld = true
	if now - fighter.blockReleasedAt < Combat.BlockRepressDelay then
		-- Mashing F: this press still blocks (after the delay) but can't close block.
		fighter.blockPressAt = -math.huge
		return
	end
	fighter.blockPressAt = Fighter.pressTime(payload.t, now)
	if fighter.state ~= "Free" then
		return -- remembered; the block starts once the fighter is free
	end
	fighter.state = "Blocking"
	fighter.blockStart = fighter.blockPressAt
end

local function onBlockEnd(fighter: Fighter, now: number)
	fighter.blockHeld = false
	fighter.blockReleasedAt = now
	if fighter.state == "Blocking" then
		fighter.state = "Free"
		fighter.blockStart = nil
	end
	-- In blockstun you stay blocking until it ends, then Fighter.release frees you.
end

local function onDodge(fighter: Fighter, now: number)
	local ok = (fighter.state == "Free" or fighter.state == "Blocking")
		and fighter.action == nil
		and Fighter.cooldownReady(fighter, "Dodge", now)
	if not ok then
		ServerNet.toPlayer(fighter.player, "DodgeRejected", {})
		return
	end
	local dodge = fighter.def.movement.dodge or Movement.Dodge
	fighter.blockStart = nil
	Fighter.setState(fighter, "Dodging", dodge.Duration, now, "Dodge")
	Fighter.setCooldown(fighter, "Dodge", now + dodge.Cooldown)
end

local function onAction(player: Player, name: any, payload: any)
	if type(name) ~= "string" then
		return
	end
	local fighter = Fighter.get(player.Character)
	if fighter == nil or fighter.state == "Downed" then
		return
	end
	local data: { [string]: any } = if type(payload) == "table" then payload else {}
	local now = Clock.now()

	if name == "M1" then
		local variant = data.variant
		if variant ~= "standing" and variant ~= "forward" and variant ~= "air" then
			return
		end
		Actions.tryM1(fighter, variant, aimFrom(data, fighter), now)
	elseif name == "BlockStart" then
		onBlockStart(fighter, data, now)
	elseif name == "BlockEnd" then
		onBlockEnd(fighter, now)
	elseif name == "Dodge" then
		onDodge(fighter, now)
	elseif name == "Sprint" then
		fighter.sprinting = data.on == true
	elseif name == "Airborne" then
		fighter.airborne = data.on == true
	elseif name == "Ability" then
		local slot = data.slot
		local kit = fighter.kit
		if type(slot) == "string" and kit and kit.ability then
			data.aim = aimFrom(data, fighter)
			kit.ability(fighter, slot, data, now)
		end
	elseif name == "Kit" then
		local message = data.message
		local kit = fighter.kit
		if type(message) == "string" and kit and kit.message then
			kit.message(fighter, message, data, now)
		end
	end
end

-- Loop ----------------------------------------------------------------------------------------

local lastNow = 0

local function step()
	local now = Clock.now()
	local dt = math.max(0, now - lastNow)
	lastNow = now

	local fighters = table.clone(Fighter.all)
	for _, fighter in fighters do
		if fighter.destroyed then
			continue
		end
		Fighter.update(fighter, now, dt)
		Actions.step(fighter, now)
		local kit = fighter.kit
		if kit and kit.update then
			kit.update(fighter, now, dt)
		end
		HitResolver.stepKnockback(fighter, now)
	end

	Projectiles.step(now, dt)
	DummyService.step(now, dt)

	for _, fighter in Fighter.all do
		Fighter.sync(fighter, now)
		if fighter.player and fighter.root.Position.Y < Movement.KillPlaneY then
			fighter.root.CFrame = spawnCFrame
			fighter.root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

function CombatService.init(spawn: CFrame)
	spawnCFrame = spawn
	lastNow = Clock.now()
	Net.Action.OnServerEvent:Connect(onAction)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	RunService.Heartbeat:Connect(step)
end

return CombatService
