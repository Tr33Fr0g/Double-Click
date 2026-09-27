--!strict
-- Game time. Every combat timer (phases, stuns, cooldowns, stacks) runs on this clock
-- instead of os.clock so debug mode can slow the whole game down, pause it, and step it
-- one frame at a time. The server owns the clock and replicates it as one attribute so
-- clients compute exactly the same time.
--   gameTime = anchorGame + (serverTime - anchorServer) * scale

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(script.Parent.Signal)

local ATTRIBUTE = "DC_Clock"

local Clock = {}

local isServer = RunService:IsServer()
local scale = 1
local anchorServer = 0
local anchorGame = 0
local stepToken = 0

-- Fires with (newScale, oldScale) whenever the time scale changes.
Clock.ScaleChanged = Signal.new() :: Signal.Signal<number, number>
-- Fires whenever a paused clock is stepped forward.
Clock.Stepped = Signal.new() :: Signal.Signal<number>

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function publish()
	ReplicatedStorage:SetAttribute(
		ATTRIBUTE,
		string.format("%.9g|%.6f|%.6f|%d", scale, anchorServer, anchorGame, stepToken)
	)
end

local function parse(value: any)
	if type(value) ~= "string" then
		return
	end
	local parts = string.split(value, "|")
	local newScale = tonumber(parts[1])
	local newAnchorServer = tonumber(parts[2])
	local newAnchorGame = tonumber(parts[3])
	local newToken = tonumber(parts[4])
	if not (newScale and newAnchorServer and newAnchorGame and newToken) then
		return
	end
	local oldScale = scale
	local oldToken = stepToken
	scale, anchorServer, anchorGame, stepToken = newScale, newAnchorServer, newAnchorGame, newToken
	if oldScale ~= scale then
		Clock.ScaleChanged:Fire(scale, oldScale)
	end
	if oldToken ~= stepToken then
		Clock.Stepped:Fire(stepToken)
	end
end

function Clock.now(): number
	return anchorGame + (serverNow() - anchorServer) * scale
end

function Clock.scale(): number
	return scale
end

function Clock.isPaused(): boolean
	return scale == 0
end

-- Server only.
function Clock.setScale(newScale: number)
	assert(isServer, "Clock.setScale is server-only")
	newScale = math.max(0, newScale)
	if newScale == scale then
		return
	end
	local oldScale = scale
	anchorGame = Clock.now()
	anchorServer = serverNow()
	scale = newScale
	publish()
	Clock.ScaleChanged:Fire(scale, oldScale)
end

-- Server only. Advances a paused clock by `dt` seconds of game time.
function Clock.step(dt: number)
	assert(isServer, "Clock.step is server-only")
	if scale ~= 0 then
		return
	end
	anchorGame += dt
	stepToken += 1
	publish()
	Clock.Stepped:Fire(stepToken)
end

function Clock.init()
	if isServer then
		anchorServer = serverNow()
		anchorGame = 0
		publish()
	else
		parse(ReplicatedStorage:GetAttribute(ATTRIBUTE))
		ReplicatedStorage:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
			parse(ReplicatedStorage:GetAttribute(ATTRIBUTE))
		end)
	end
end

return Clock
