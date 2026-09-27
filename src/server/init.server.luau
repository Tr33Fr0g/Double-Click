--!strict
-- Double Click beta: server entry point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CombatService = require(script.CombatService)
local DebugService = require(script.DebugService)
local DummyService = require(script.DummyService)
local HitResolver = require(script.HitResolver)
local MapBuilder = require(script.MapBuilder)
local Projectiles = require(script.Projectiles)

Clock.init()
DebugService.init()

local map = MapBuilder.build()
HitResolver.setArena(map.arena)
Projectiles.init(map.effects, map.arena)
ReplicatedStorage:SetAttribute("DC_Version", GameConfig.Version)

CombatService.init(map.spawns[1])
DummyService.init(map.dummies, map.dummySpawns)

print(`[Double Click] {GameConfig.Version} server started.`)
