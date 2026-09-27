--!strict
-- Placeholder animations for every fighter, driven by the attributes the server
-- replicates (doc: "Every move gets a simple animation showing its wind-up, active and
-- recovery phases"). Joint offsets are layered on top of Roblox's default walk/idle.
-- Also shows a phase tint (yellow wind-up, red active, blue recovery), a shield while
-- blocking/parrying/countering, and a ghosted body while Speerrow can't be hit.
-- Runs on game time, so it slows down, pauses and frame-steps with debug mode.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Attr = require(Shared.Util.Attr)
local Clock = require(Shared.Util.Clock)
local GameConfig = require(Shared.Config.GameConfig)
local Poses = require(Shared.Anim.Poses)

type JointInfo = { motor: Motor6D, base: CFrame }

type Rig = {
	model: Model,
	joints: { [string]: JointInfo }, -- keyed by Poses.Joint
	current: { [string]: Vector3 },
	highlight: Highlight,
	shield: Part,
	ghosted: boolean,
}

local Animator = {}

local rigs: { [Model]: Rig } = {}
local lastTime = 0

local JOINT_NAMES: { [string]: { string } } = {
	Torso = { "Waist", "RootJoint" },
	Head = { "Neck" },
	RightArm = { "RightShoulder", "Right Shoulder" },
	LeftArm = { "LeftShoulder", "Left Shoulder" },
	RightLeg = { "RightHip", "Right Hip" },
	LeftLeg = { "LeftHip", "Left Hip" },
}

local PHASE_COLORS = GameConfig.Debug.Colors
local SHIELD_COLORS = {
	Blocking = Color3.fromRGB(90, 160, 255),
	Blockstun = Color3.fromRGB(150, 190, 255),
	Parrying = Color3.fromRGB(255, 235, 170),
	Countering = Color3.fromRGB(255, 70, 70),
}
local STATE_POSES = {
	Blocking = "Block",
	Blockstun = "Blockstun",
	Hitstun = "Hitstun",
	Stunned = "Stunned",
	Downed = "Downed",
	Rushing = "Rush",
	Dodging = "Dodge",
	Parrying = "Parry",
	Countering = "Counter",
	Recovery = "Recovery",
}
local NEUTRAL: Poses.Pose = {}

local function findJoints(model: Model): { [string]: JointInfo }
	local joints: { [string]: JointInfo } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			for joint, names in JOINT_NAMES do
				if not joints[joint] and table.find(names, descendant.Name) then
					joints[joint] = { motor = descendant, base = descendant.C0 }
				end
			end
		end
	end
	return joints
end

local function effectsFolder(): Instance
	return workspace:FindFirstChild("DC_ClientEffects") or workspace
end

local function register(model: Model)
	if rigs[model] then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "DC_PhaseTint"
	highlight.Enabled = false
	highlight.FillTransparency = 0.72
	highlight.OutlineTransparency = 0.35
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model

	local shield = Instance.new("Part")
	shield.Name = "DC_Shield"
	shield.Size = Vector3.new(4.6, 5.2, 0.35)
	shield.Material = Enum.Material.ForceField
	shield.Anchored = true
	shield.CanCollide = false
	shield.CanQuery = false
	shield.CanTouch = false
	shield.CastShadow = false
	shield.Transparency = 1
	shield.Parent = effectsFolder()

	rigs[model] = {
		model = model,
		joints = {},
		current = {},
		highlight = highlight,
		shield = shield,
		ghosted = false,
	}
end

local function unregister(model: Model)
	local rig = rigs[model]
	if rig then
		rigs[model] = nil
		rig.shield:Destroy()
		rig.highlight:Destroy()
	end
end

local function stringAttr(model: Model, name: string): string
	local value = model:GetAttribute(name)
	return if type(value) == "string" then value else ""
end

-- The pose to blend toward, and how quickly.
local function targetPose(model: Model): (Poses.Pose, number)
	local state = stringAttr(model, Attr.State)
	local pose = stringAttr(model, Attr.Pose)
	local phase = stringAttr(model, Attr.Phase)

	if phase ~= "" then
		local attack = Poses.Attack[pose]
		if attack then
			if phase == "Windup" then
				return attack.windup, 28
			elseif phase == "Active" then
				return attack.active, 45
			end
			return NEUTRAL, 9
		end
	end
	local statePose = Poses.State[pose] or Poses.State[STATE_POSES[state] or ""]
	if statePose then
		return statePose, 22
	end
	return NEUTRAL, 14
end

local function setGhost(rig: Rig, on: boolean)
	if rig.ghosted == on then
		return
	end
	rig.ghosted = on
	for _, descendant in rig.model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "DC_Hurtbox" and descendant.Name ~= "HumanoidRootPart" then
			descendant.LocalTransparencyModifier = if on then 0.6 else 0
		end
	end
end

local function updateRig(rig: Rig, dt: number)
	local model = rig.model
	if next(rig.joints) == nil then
		rig.joints = findJoints(model)
	end

	local pose, sharpness = targetPose(model)
	local alpha = 1 - math.exp(-sharpness * dt)
	for joint, info in rig.joints do
		if info.motor.Parent == nil then
			continue
		end
		local want = pose[joint] or Vector3.zero
		local current = (rig.current[joint] or Vector3.zero):Lerp(want, alpha)
		rig.current[joint] = current
		if current.Magnitude < 0.05 then
			info.motor.C0 = info.base
		else
			local rotation = CFrame.Angles(math.rad(current.X), math.rad(current.Y), math.rad(current.Z))
			info.motor.C0 = CFrame.new(info.base.Position) * rotation * info.base.Rotation
		end
	end

	local phase = stringAttr(model, Attr.Phase)
	local phaseColor = if phase == "Windup"
		then PHASE_COLORS.Windup
		elseif phase == "Active" then PHASE_COLORS.Active
		elseif phase == "Recovery" then PHASE_COLORS.Recovery
		else nil
	rig.highlight.Enabled = phaseColor ~= nil
	if phaseColor then
		rig.highlight.FillColor = phaseColor
		rig.highlight.OutlineColor = phaseColor
	end

	local state = stringAttr(model, Attr.State)
	local shieldColor = SHIELD_COLORS[state]
	local root = model:FindFirstChild("HumanoidRootPart")
	if shieldColor and root and root:IsA("BasePart") then
		rig.shield.Color = shieldColor
		rig.shield.Transparency = 0.35
		rig.shield.CFrame = root.CFrame * CFrame.new(0, 0, -1.9)
	else
		rig.shield.Transparency = 1
	end

	setGhost(rig, model:GetAttribute(Attr.Intangible) == true)
end

local function step()
	local now = Clock.now()
	local dt = math.clamp(now - lastTime, 0, 0.1)
	lastTime = now
	for model, rig in rigs do
		if model.Parent == nil then
			unregister(model)
		else
			updateRig(rig, dt)
		end
	end
end

function Animator.init()
	lastTime = Clock.now()
	CollectionService:GetInstanceAddedSignal(Attr.Tag):Connect(function(instance)
		if instance:IsA("Model") then
			register(instance)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(Attr.Tag):Connect(function(instance)
		if instance:IsA("Model") then
			unregister(instance)
		end
	end)
	for _, instance in CollectionService:GetTagged(Attr.Tag) do
		if instance:IsA("Model") then
			register(instance)
		end
	end
	RunService.RenderStepped:Connect(step)
end

return Animator
