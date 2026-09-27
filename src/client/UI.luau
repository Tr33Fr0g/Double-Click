--!strict
-- Tiny helpers for building placeholder UI in code.

local UI = {}

UI.Font = Enum.Font.GothamBold
UI.BodyFont = Enum.Font.Gotham
UI.Background = Color3.fromRGB(18, 20, 26)
UI.Panel = Color3.fromRGB(30, 33, 42)
UI.Text = Color3.fromRGB(235, 238, 245)
UI.Muted = Color3.fromRGB(150, 156, 170)
UI.Accent = Color3.fromRGB(80, 200, 255)

function UI.new(className: string, props: { [string]: any }, children: { any }?): Instance
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

function UI.corner(radius: number): Instance
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	return corner
end

function UI.stroke(color: Color3, thickness: number, transparency: number?): Instance
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return stroke
end

function UI.padding(pixels: number): Instance
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	return padding
end

function UI.list(padding: number, direction: Enum.FillDirection?): Instance
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding)
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	return layout
end

function UI.label(text: string, size: number, props: { [string]: any }?): TextLabel
	local label = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		Font = UI.Font,
		TextColor3 = UI.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, size + 4),
	}) :: TextLabel
	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	return label
end

-- A horizontal bar: returns the container and the fill frame (scale the fill's X).
function UI.bar(color: Color3, height: number): (Frame, Frame)
	local fill = UI.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, { UI.corner(math.floor(height / 2)) }) :: Frame
	local container = UI.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(12, 13, 17),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height),
	}, { UI.corner(math.floor(height / 2)), fill }) :: Frame
	return container, fill
end

return UI
