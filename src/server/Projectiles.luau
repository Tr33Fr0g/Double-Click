--!strict
-- Server-simulated projectiles (the training dummy's arrows). Ranged attacks can be
-- parried: the damage is cancelled, but nothing reflects back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Teams = require(Shared.Util.Teams)
local Types = require(Shared.Types)

local Fighter = require(script.Parent.Fighter)
local HitResolver = require(script.Parent.HitResolver)

type Fighter = Fighter.Fighter

type Projectile = {
	owner: Fighter,
	move: Types.MoveDef,
	part: BasePart,
	position: Vector3,
	direction: Vector3,
	traveled: number,
	ignore: { Instance },
}

local Projectiles = {}

local active: { Projectile } = {}
local effectsFolder: Instance = workspace
local arena: Instance = workspace

function Projectiles.init(effects: Instance, arenaFolder: Instance)
	effectsFolder = effects
	arena = arenaFolder
end

function Projectiles.spawn(owner: Fighter, move: Types.MoveDef, origin: Vector3, direction: Vector3)
	local def = move.projectile
	if not def or direction.Magnitude < 1e-3 then
		return
	end
	direction = direction.Unit
	local part: BasePart = Instance.new("Part")
	part.Name = move.name
	part.Size = def.size
	part.Material = Enum.Material.Neon
	part.Color = owner.def.color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.lookAt(origin, origin + direction)
	part.Parent = effectsFolder
	table.insert(active, {
		owner = owner,
		move = move,
		part = part,
		position = origin,
		direction = direction,
		traveled = 0,
		ignore = { owner.hurtbox },
	})
end

local function remove(index: number)
	local projectile = active[index]
	projectile.part:Destroy()
	table.remove(active, index)
end

function Projectiles.step(now: number, dt: number)
	if dt <= 0 then
		return
	end
	for index = #active, 1, -1 do
		local projectile = active[index]
		local def = projectile.move.projectile :: Types.ProjectileDef
		local distance = math.min(def.speed * dt, def.range - projectile.traveled)
		if distance <= 0 or projectile.owner.destroyed then
			remove(index)
			continue
		end

		local include: { Instance } = { arena }
		for _, hurtbox in Fighter.hurtboxes() do
			if not table.find(projectile.ignore, hurtbox) then
				table.insert(include, hurtbox)
			end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = include

		local result = workspace:Raycast(projectile.position, projectile.direction * distance, params)
		if result then
			local target = Fighter.byHurtbox[result.Instance :: BasePart]
			if target == nil then
				remove(index) -- hit the map
				continue
			end
			local passThrough = true
			if Teams.areEnemies(projectile.owner.model, target.model) then
				local outcome = HitResolver.resolve(projectile.owner, target, projectile.move, {
					projectile = true,
					direction = projectile.direction,
					origin = result.Position,
					time = now,
				})
				passThrough = outcome == "Ignored"
			end
			if not passThrough then
				remove(index)
				continue
			end
			-- Teammates and intangible targets let it fly on.
			table.insert(projectile.ignore, target.hurtbox)
		end

		projectile.position += projectile.direction * distance
		projectile.traveled += distance
		projectile.part.CFrame = CFrame.lookAt(projectile.position, projectile.position + projectile.direction)
	end
end

function Projectiles.clear()
	for index = #active, 1, -1 do
		remove(index)
	end
end

return Projectiles
