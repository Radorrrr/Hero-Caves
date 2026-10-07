local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EnemyService = require(script.Parent.EnemyService)
local Contexts = require(script.Parent.CombatContexts)

local WaveService = {}
local function startWave(context, wave)
	if not Contexts.IsActive(context) then return end
	context.CurrentWave = wave
	context.Folder:SetAttribute("Wave", wave)
	context.Player:SetAttribute("IdleHeroSimulatorWave", wave)
	EnemyService.Spawn(context, wave, wave % GameConfig.BossEveryWaves == 0)
end
local function scheduleWave(context, wave)
	context.PendingWave = wave
	context.NextSpawnAt = time() + GameConfig.WaveDelay
end
function WaveService.GetCurrentWave(context)
	return Contexts.IsActive(context) and context.CurrentWave or 0
end
function WaveService.Start(context)
	if not Contexts.IsActive(context) or context.WaveConnection then return end
	startWave(context, 1)
	context.WaveConnection = RunService.Heartbeat:Connect(function()
		if not Contexts.IsActive(context) then return end
		if context.PendingWave then
			if time() >= context.NextSpawnAt then
				local wave = context.PendingWave
				context.PendingWave, context.NextSpawnAt = nil, nil
				startWave(context, wave)
			end
			return
		end
		local enemy = EnemyService.GetActiveEnemy(context)
		if not enemy then
			scheduleWave(context, context.CurrentWave + 1)
		elseif enemy.IsBoss and time() >= enemy.Deadline then
			EnemyService.Remove(context)
			scheduleWave(context, context.CurrentWave - 1)
		elseif enemy.IsBoss then
			EnemyService.UpdateDisplay(context)
		end
	end)
end
function WaveService.Stop(context)
	if context.WaveConnection then context.WaveConnection:Disconnect(); context.WaveConnection = nil end
	context.PendingWave, context.NextSpawnAt = nil, nil
end
return WaveService
