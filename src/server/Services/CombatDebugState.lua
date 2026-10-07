local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local Contexts = require(script.Parent.CombatContexts)
local CombatDebugState = {}
local changed = Instance.new("BindableEvent")
CombatDebugState.Changed = changed.Event
local states = {}
function CombatDebugState.IsAvailable()
	return RunService:IsStudio() and GameConfig.StudioTesting.Enabled == true
end
function CombatDebugState.IsPaused(player)
	return CombatDebugState.IsAvailable() and states[player] ~= nil and states[player].Paused == true
end
function CombatDebugState.IsHeroSelected(player, id)
	return not states[player] or states[player].Enabled[id] ~= false
end
function CombatDebugState.IsHeroEnabled(player, id)
	return not CombatDebugState.IsAvailable() or (not CombatDebugState.IsPaused(player)
		and CombatDebugState.IsHeroSelected(player, id))
end
local function state(player)
	if not states[player] then states[player] = {Paused = false, Enabled = {}} end
	return states[player]
end
function CombatDebugState.SetPaused(player, value)
	if not CombatDebugState.IsAvailable() or not Contexts.Get(player) or type(value) ~= "boolean" then return false end
	local current = state(player)
	if current.Paused ~= value then current.Paused = value; changed:Fire(player) end
	return true
end
function CombatDebugState.SetHeroEnabled(player, id, value)
	if not CombatDebugState.IsAvailable() or not Contexts.Get(player) or type(id) ~= "string"
		or type(HeroConfig[id]) ~= "table" or not HeroConfig[id].HeroId or type(value) ~= "boolean" then return false end
	local current = state(player)
	if (current.Enabled[id] ~= false) ~= value then current.Enabled[id] = value; changed:Fire(player) end
	return true
end
function CombatDebugState.Clear(player)
	states[player] = nil
	changed:Fire(player)
end
return CombatDebugState
