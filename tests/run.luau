--!nocheck
-- Runs the pure-logic tests outside Roblox with Lune: `lune run tests/run.luau`
-- Roblox datatypes come from @lune/roblox. Game code requires modules through
-- `script` (instance paths); the shim below makes those type-only requires return nil so
-- data modules load, while specs require real modules by file path.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local env = getfenv(0)
env.Vector3 = roblox.Vector3
env.CFrame = roblox.CFrame
env.Color3 = roblox.Color3

local proxyMeta = {}
proxyMeta.__index = function()
	return setmetatable({}, proxyMeta)
end
env.script = setmetatable({}, proxyMeta)

local realRequire = require
env.require = function(target, ...)
	if type(target) == "table" and getmetatable(target) == proxyMeta then
		return nil
	end
	return realRequire(target, ...)
end

local T = require("./lib")

local files = {}
for _, name in fs.readDir("tests") do
	if string.match(name, "%.spec%.luau$") then
		table.insert(files, name)
	end
end
table.sort(files)

for _, name in files do
	T.file(name)
	require("./" .. string.gsub(name, "%.luau$", ""))
end

local passed, failed = T.summary()
print(string.format("\n%d passed, %d failed", passed, failed))
process.exit(if failed == 0 then 0 else 1)
