--!nocheck
-- Tiny test helpers for the Lune runner.

local T = {}

local passed = 0
local failed = 0
local suite = ""

function T.file(name)
	print("\n" .. name)
end

function T.describe(name, fn)
	suite = name
	fn()
	suite = ""
end

function T.it(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. suite .. " > " .. name)
	else
		failed += 1
		print("  FAIL " .. suite .. " > " .. name .. "\n       " .. tostring(err))
	end
end

local function fmt(v)
	if type(v) == "number" then
		return string.format("%.4f", v)
	end
	return tostring(v)
end

function T.eq(actual, expected, message)
	if actual ~= expected then
		error(
			string.format("%sexpected %s, got %s", message and (message .. ": ") or "", fmt(expected), fmt(actual)),
			2
		)
	end
end

function T.near(actual, expected, epsilon, message)
	epsilon = epsilon or 1e-6
	if type(actual) ~= "number" or math.abs(actual - expected) > epsilon then
		error(
			string.format(
				"%sexpected %s (+-%s), got %s",
				message and (message .. ": ") or "",
				fmt(expected),
				fmt(epsilon),
				fmt(actual)
			),
			2
		)
	end
end

function T.truthy(value, message)
	if not value then
		error(message or "expected a truthy value", 2)
	end
end

function T.summary()
	return passed, failed
end

return T
