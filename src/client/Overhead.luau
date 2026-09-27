--!strict
-- Name, HP and block meter over every other fighter, plus a state tag (STUNNED etc.).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Attr = require(Shared.Util.Attr)

local UI = require(script.Parent.UI)

type Tag = { gui: BillboardGui, hp: Frame, block: Frame, state: TextLabel }

local Overhead = {}

local tags: { [Model]: Tag } = {}

local STATE_TAGS: { [string]: { text: string, color: Color3 } } = {
	Stunned = { text = "STUNNED", color = Color3.fromRGB(255, 220, 60) },
	Hitstun = { text = "HIT", color = Color3.fromRGB(255, 150, 150) },
	Blocking = { text = "BLOCKING", color = Color3.fromRGB(120, 180, 255) },
	Blockstun = { text = "BLOCKSTUN", color = Color3.fromRGB(160, 200, 255) },
	Parrying = { text = "PARRY", color = Color3.fromRGB(255, 240, 180) },
	Countering = { text = "COUNTER", color = Color3.fromRGB(255, 90, 90) },
	Recovery = { text = "RECOVERING", color = Color3.fromRGB(200, 200, 200) },
	Downed = { text = "DOWN", color = Color3.fromRGB(160, 160, 160) },
}

local function number(model: Model, name: string, default: number): number
	local value = model:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function register(model: Model)
	if tags[model] or model == Players.LocalPlayer.Character then
		return
	end
	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if head == nil or not head:IsA("BasePart") then
		return
	end
	local hpBar, hpFill = UI.bar(Color3.fromRGB(90, 220, 120), 8)
	local blockBar, blockFill = UI.bar(Color3.fromRGB(90, 170, 255), 4)
	hpBar.LayoutOrder = 2
	blockBar.LayoutOrder = 3
	local state = UI.label("", 13, {
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
	})
	local gui = UI.new("BillboardGui", {
		Name = "DC_Overhead",
		Size = UDim2.fromOffset(120, 46),
		StudsOffset = Vector3.new(0, 2.6, 0),
		MaxDistance = 140,
		Adornee = head,
		ResetOnSpawn = false,
	}, {
		UI.list(2),
		state,
		UI.label(model.Name, 12, {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 13),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.5,
		}),
		hpBar,
		blockBar,
	}) :: BillboardGui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	tags[model] = { gui = gui, hp = hpFill, block = blockFill, state = state }
end

local function unregister(model: Model)
	local tag = tags[model]
	if tag then
		tags[model] = nil
		tag.gui:Destroy()
	end
end

local function update()
	for model, tag in tags do
		if model.Parent == nil then
			unregister(model)
			continue
		end
		tag.hp.Size = UDim2.fromScale(math.clamp(number(model, Attr.HP, 0) / number(model, Attr.MaxHP, 1), 0, 1), 1)
		tag.block.Size = UDim2.fromScale(
			math.clamp(number(model, Attr.BlockMeter, 0) / number(model, Attr.BlockMeterMax, 1), 0, 1),
			1
		)
		local stateValue = model:GetAttribute(Attr.State)
		local info = if type(stateValue) == "string" then STATE_TAGS[stateValue] else nil
		tag.state.Text = if info then info.text else ""
		if info then
			tag.state.TextColor3 = info.color
		end
	end
end

function Overhead.init()
	CollectionService:GetInstanceAddedSignal(Attr.Tag):Connect(function(instance)
		if instance:IsA("Model") then
			task.defer(register, instance)
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
	RunService.RenderStepped:Connect(update)
end

return Overhead
