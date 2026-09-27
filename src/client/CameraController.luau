--!strict
-- Over-the-shoulder free aim by default (like Fortnite) with an optional lock-on that
-- keeps the camera on one enemy (like Elden Ring). Middle mouse toggles lock-on.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Attr = require(Shared.Util.Attr)
local GameConfig = require(Shared.Config.GameConfig)
local Teams = require(Shared.Util.Teams)

local Me = require(script.Parent.Me)

local Cam = GameConfig.Camera

local CameraController = {}

local camera = workspace.CurrentCamera
local yaw = 0
local pitch = math.rad(-12)
local pivot: Vector3? = nil
local lockTarget: Model? = nil
local mouseFree = false
local sprinting = false
local shake = 0
local reticle: BillboardGui? = nil
local blockers = RaycastParams.new()
blockers.FilterType = Enum.RaycastFilterType.Include

local function targetRoot(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isValidTarget(model: Model, origin: Vector3, range: number): boolean
	local body = Me.body
	if body == nil or model == body.character or model.Parent == nil then
		return false
	end
	if model:GetAttribute(Attr.State) == "Downed" or not Teams.areEnemies(body.character, model) then
		return false
	end
	local root = targetRoot(model)
	return root ~= nil and (root.Position - origin).Magnitude <= range
end

local function angleWrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

function CameraController.yaw(): number
	return yaw
end

-- Where attacks go: at the lock-on target, else where the camera is looking.
function CameraController.aim(): Vector3
	local body = Me.body
	local target = lockTarget
	if body and target then
		local root = targetRoot(target)
		if root then
			local offset = root.Position - body.root.Position
			if offset.Magnitude > 1e-3 then
				return offset.Unit
			end
		end
	end
	return camera.CFrame.LookVector
end

function CameraController.flatAim(): Vector3
	local aim = CameraController.aim()
	local flat = Vector3.new(aim.X, 0, aim.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
end

function CameraController.lockTarget(): Model?
	return lockTarget
end

function CameraController.setMouseFree(free: boolean)
	mouseFree = free
end

function CameraController.setSprinting(on: boolean)
	sprinting = on
end

function CameraController.shake(amount: number)
	shake = math.max(shake, amount)
end

function CameraController.toggleLock()
	if lockTarget then
		lockTarget = nil
		return
	end
	local body = Me.body
	if body == nil then
		return
	end
	local origin = body.root.Position
	local look = camera.CFrame.LookVector
	local best: Model? = nil
	local bestScore = math.huge
	local maxAngle = math.rad(Cam.LockOn.MaxAngleDeg)
	for _, instance in CollectionService:GetTagged(Attr.Tag) do
		if instance:IsA("Model") and isValidTarget(instance, origin, Cam.LockOn.Range) then
			local root = targetRoot(instance) :: BasePart
			local offset = root.Position - camera.CFrame.Position
			local angle = math.acos(math.clamp(look:Dot(offset.Unit), -1, 1))
			-- Prefer targets near the crosshair; fall back to the nearest one.
			local score = if angle <= maxAngle then angle else 10 + offset.Magnitude
			if score < bestScore then
				best = instance
				bestScore = score
			end
		end
	end
	lockTarget = best
end

local function update(dt: number)
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = if mouseFree then Enum.MouseBehavior.Default else Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = mouseFree

	local body = Me.body
	if body == nil then
		return
	end

	if not mouseFree then
		local delta = UserInputService:GetMouseDelta()
		local sensitivity = math.rad(Cam.Sensitivity)
		yaw -= delta.X * sensitivity
		pitch -= delta.Y * sensitivity
	end

	local target = lockTarget
	if target and not isValidTarget(target, body.root.Position, Cam.LockOn.Range * 1.2) then
		lockTarget = nil
		target = nil
	end
	local marker = reticle
	if marker then
		local adornee = if target then targetRoot(target) else nil
		if adornee then
			marker.Adornee = adornee
		end
		marker.Enabled = adornee ~= nil
	end
	if target then
		local root = targetRoot(target) :: BasePart
		local from = body.root.Position + Vector3.new(0, Cam.PivotHeight, 0)
		local offset = (root.Position + Vector3.new(0, 0.5, 0)) - from
		if offset.Magnitude > 1e-3 then
			local dir = offset.Unit
			local wantYaw = math.atan2(-dir.X, -dir.Z)
			local wantPitch = math.asin(math.clamp(dir.Y, -1, 1)) - math.rad(8)
			local alpha = 1 - math.exp(-Cam.LockOn.TurnSharpness * dt)
			yaw += angleWrap(wantYaw - yaw) * alpha
			pitch += (wantPitch - pitch) * alpha
		end
	end
	pitch = math.clamp(pitch, math.rad(Cam.PitchMinDeg), math.rad(Cam.PitchMaxDeg))
	yaw = angleWrap(yaw)

	local wantPivot = body.root.Position + Vector3.new(0, Cam.PivotHeight, 0)
	local current = pivot
	if current == nil or (current - wantPivot).Magnitude > 30 then
		current = wantPivot
	else
		current = current:Lerp(wantPivot, 1 - math.exp(-Cam.FollowSharpness * dt))
	end
	pivot = current
	local focus = current :: Vector3

	local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local offset = rotation:VectorToWorldSpace(Vector3.new(Cam.ShoulderOffset.X, Cam.ShoulderOffset.Y, Cam.Distance))
	local arena = workspace:FindFirstChild("Arena")
	local solid = arena and (arena:FindFirstChild("Solid") or arena)
	local distance = offset.Magnitude
	if solid then
		blockers.FilterDescendantsInstances = { solid }
		local hit = workspace:Spherecast(focus, Cam.CollisionRadius, offset, blockers)
		if hit then
			distance = math.max(0.5, hit.Distance - 0.1)
		end
	end
	local position = focus + offset.Unit * distance

	if shake > 0.01 then
		local t = os.clock() * 40
		position += rotation:VectorToWorldSpace(Vector3.new(math.noise(t, 0) * shake, math.noise(0, t) * shake, 0))
		shake *= math.exp(-12 * dt)
	end

	camera.CFrame = CFrame.new(position) * rotation
	local wantFov = if sprinting then Cam.SprintFieldOfView else Cam.FieldOfView
	camera.FieldOfView += (wantFov - camera.FieldOfView) * (1 - math.exp(-6 * dt))
end

local function buildReticle()
	local gui = Instance.new("BillboardGui")
	gui.Name = "DC_LockOn"
	gui.Size = UDim2.fromOffset(34, 34)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.ResetOnSpawn = false
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(26, 26)
	ring.BackgroundTransparency = 1
	ring.Rotation = 45
	ring.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 80, 80)
	stroke.Thickness = 2.5
	stroke.Parent = ring
	gui.Parent = Me.player:WaitForChild("PlayerGui")
	reticle = gui
end

function CameraController.init()
	task.spawn(buildReticle)
	Me.Spawned:Connect(function(body)
		pivot = nil
		lockTarget = nil
		local look = body.root.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
	end)
	RunService:BindToRenderStep("DC_Camera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
