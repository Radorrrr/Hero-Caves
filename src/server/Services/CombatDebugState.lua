local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)

local CombatDebugState = {}
local changed = Instance.new("BindableEvent")
CombatDebugState.Changed = changed.Event
local paused = false
local enabled = {}

function CombatDebugState.IsAvailable()
	return RunService:IsStudio() and GameConfig.StudioTesting.Enabled == true
end

function CombatDebugState.IsPaused()
	return CombatDebugState.IsAvailable() and paused
end

function CombatDebugState.IsHeroEnabled(heroId)
	return not CombatDebugState.IsAvailable() or (not paused and enabled[heroId] ~= false)
end

function CombatDebugState.IsHeroSelected(heroId)
	return enabled[heroId] ~= false
end

function CombatDebugState.SetPaused(value)
	if not CombatDebugState.IsAvailable() or type(value) ~= "boolean" then return false end
	if paused ~= value then
		paused = value
		changed:Fire()
	end
	return true
end

function CombatDebugState.SetHeroEnabled(heroId, value)
	if not CombatDebugState.IsAvailable() or type(heroId) ~= "string"
		or type(HeroConfig[heroId]) ~= "table" or not HeroConfig[heroId].HeroId
		or type(value) ~= "boolean" then return false end
	if (enabled[heroId] ~= false) ~= value then
		enabled[heroId] = value
		changed:Fire()
	end
	return true
end

return CombatDebugState
