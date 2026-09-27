--!strict
-- Builds the beta test arena at runtime: an open map with natural walls (cliffs, rocks,
-- big trees) and mountains at the edges so nobody can fall off (doc: "Maps").
-- Tall trees in one corner are Speerrow's playground for Rush tree-hopping.
-- If the place already has a Workspace.Arena folder, that map is used instead.

local MapBuilder = {}

export type Map = {
	arena: Folder, -- everything solid (walls, trees, ground)
	cameraBlockers: Folder, -- solid things the camera should not clip through
	effects: Folder,
	dummies: Folder,
	spawns: { CFrame },
	dummySpawns: { CFrame },
}

local SIZE = 420
local GRASS = Color3.fromRGB(96, 150, 72)
local ROCK = Color3.fromRGB(120, 116, 110)
local CLIFF = Color3.fromRGB(135, 118, 96)
local BARK = Color3.fromRGB(99, 72, 52)
local LEAVES = Color3.fromRGB(62, 120, 60)

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function tree(solid: Instance, foliage: Instance, position: Vector3, height: number, trunkWidth: number)
	local trunk = part(
		solid,
		"Trunk",
		Vector3.new(height, trunkWidth, trunkWidth),
		CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		BARK,
		Enum.Material.Wood
	)
	trunk.Shape = Enum.PartType.Cylinder
	local canopy = part(
		foliage,
		"Canopy",
		Vector3.new(1, 1, 1) * (trunkWidth * 4),
		CFrame.new(position + Vector3.new(0, height, 0)),
		LEAVES,
		Enum.Material.Grass
	)
	canopy.Shape = Enum.PartType.Ball
end

local function build(): Map
	local root = Instance.new("Folder")
	root.Name = "Arena"
	local solid = Instance.new("Folder")
	solid.Name = "Solid"
	solid.Parent = root
	local foliage = Instance.new("Folder")
	foliage.Name = "Foliage"
	foliage.Parent = root

	-- Ground
	part(solid, "Ground", Vector3.new(SIZE, 4, SIZE), CFrame.new(0, -2, 0), GRASS, Enum.Material.Grass)

	-- Mountains around the edge, plus an invisible barrier above them.
	local half = SIZE / 2
	for i, spec in { { 0, -half }, { 0, half }, { -half, 0 }, { half, 0 } } do
		local x, z = spec[1], spec[2]
		local alongX = z ~= 0
		local size = if alongX then Vector3.new(SIZE + 80, 90, 40) else Vector3.new(40, 90, SIZE + 80)
		part(solid, "Mountain" .. i, size, CFrame.new(x, 45, z), ROCK, Enum.Material.Slate)
		local barrier = part(
			root,
			"Barrier" .. i,
			if alongX then Vector3.new(SIZE + 80, 400, 4) else Vector3.new(4, 400, SIZE + 80),
			CFrame.new(x, 200, z),
			ROCK,
			Enum.Material.SmoothPlastic
		)
		barrier.Transparency = 1
		barrier.CanQuery = false
		-- Peaks for looks
		for j = -2, 2 do
			local offset = j * (SIZE / 5)
			local peakPosition = if alongX then Vector3.new(offset, 100, z) else Vector3.new(x, 100, offset)
			local peak = part(
				solid,
				"Peak",
				Vector3.new(60, 50, 60),
				CFrame.new(peakPosition) * CFrame.Angles(0, math.rad(45 + j * 13), 0),
				ROCK:Lerp(Color3.new(1, 1, 1), 0.05 * (j + 2)),
				Enum.Material.Slate
			)
			peak.Shape = Enum.PartType.Block
		end
	end

	-- Rocks (natural walls for wall jumps and wall stuns)
	local rocks = {
		{ position = Vector3.new(40, 0, -30), size = Vector3.new(18, 14, 12), yaw = 20 },
		{ position = Vector3.new(-50, 0, 20), size = Vector3.new(14, 20, 14), yaw = -35 },
		{ position = Vector3.new(10, 0, 60), size = Vector3.new(26, 10, 10), yaw = 10 },
		{ position = Vector3.new(-20, 0, -70), size = Vector3.new(12, 16, 22), yaw = 60 },
		{ position = Vector3.new(80, 0, 40), size = Vector3.new(20, 24, 16), yaw = -15 },
		{ position = Vector3.new(-90, 0, -40), size = Vector3.new(16, 12, 16), yaw = 45 },
	}
	for _, rock in rocks do
		part(
			solid,
			"Rock",
			rock.size,
			CFrame.new(rock.position + Vector3.new(0, rock.size.Y / 2, 0)) * CFrame.Angles(0, math.rad(rock.yaw), 0),
			ROCK,
			Enum.Material.Rock
		)
	end

	-- A cliff with a ramp up (steep face for wall jumps, height matters a little).
	part(solid, "Cliff", Vector3.new(70, 22, 50), CFrame.new(-130, 11, 110), CLIFF, Enum.Material.Sandstone)
	local ramp = Instance.new("WedgePart")
	ramp.Name = "Ramp"
	ramp.Anchored = true
	ramp.Size = Vector3.new(24, 22, 50)
	ramp.CFrame = CFrame.new(-130, 11, 60) * CFrame.Angles(0, math.rad(180), 0)
	ramp.Color = CLIFF
	ramp.Material = Enum.Material.Sandstone
	ramp.Parent = solid

	-- Scattered big trees
	for _, position in
		{
			Vector3.new(60, 0, -80),
			Vector3.new(-60, 0, 80),
			Vector3.new(110, 0, -20),
			Vector3.new(-110, 0, -110),
			Vector3.new(30, 0, 120),
			Vector3.new(-140, 0, 20),
		}
	do
		tree(solid, foliage, position, 42, 6)
	end

	-- Tall-tree grove: trunks ~11 studs apart so Rush can hop between them.
	for row = 0, 3 do
		for column = 0, 3 do
			local jitter = ((row * 7 + column * 3) % 5) - 2
			local position = Vector3.new(110 + column * 16 + jitter, 0, 100 + row * 16 - jitter)
			tree(solid, foliage, position, 80 + ((row + column) % 3) * 8, 5)
		end
	end

	-- Training area markings
	local pad = part(
		root,
		"TrainingPad",
		Vector3.new(50, 0.2, 30),
		CFrame.new(0, 0.1, -40),
		Color3.fromRGB(80, 90, 110),
		Enum.Material.Concrete
	)
	pad.CanCollide = false
	pad.CanQuery = false

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(90, 110, 150)
	spawn.Material = Enum.Material.Concrete
	spawn.Parent = root

	root.Parent = workspace

	local dummySpawns = {}
	for i = -1, 1 do
		local position = Vector3.new(i * 12, 0, -45)
		table.insert(dummySpawns, CFrame.lookAt(position, position + Vector3.new(0, 0, 1)))
	end

	return {
		arena = root,
		cameraBlockers = solid,
		effects = Instance.new("Folder"),
		dummies = Instance.new("Folder"),
		spawns = { CFrame.new(0, 3, 0) },
		dummySpawns = dummySpawns,
	}
end

function MapBuilder.build(): Map
	local existing = workspace:FindFirstChild("Arena")
	local map: Map
	if existing and existing:IsA("Folder") then
		local solid = existing:FindFirstChild("Solid")
		map = {
			arena = existing,
			cameraBlockers = if solid and solid:IsA("Folder") then solid else existing,
			effects = Instance.new("Folder"),
			dummies = Instance.new("Folder"),
			spawns = { CFrame.new(0, 3, 0) },
			dummySpawns = { CFrame.new(0, 0, -45) },
		}
	else
		map = build()
	end

	map.effects.Name = "DC_Effects"
	map.effects.Parent = workspace
	map.dummies.Name = "DC_Dummies"
	map.dummies.Parent = workspace
	return map
end

return MapBuilder
