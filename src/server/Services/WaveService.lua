local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EnemyService = require(script.Parent.EnemyService)

local WaveService = {}
local connection = nil
local currentWave = 0
local pendingWave = nil
local nextSpawnAt = nil

local function startWave(wave)
	currentWave = wave
	workspace:SetAttribute("HeroCavesWave", wave)
	if GameConfig.DebugLogging then
		print(string.format("[WaveService] Starting Wave %d", wave))
	end
	EnemyService.Spawn(wave, wave % GameConfig.BossEveryWaves == 0)
end

local function scheduleWave(wave)
	pendingWave = wave
	nextSpawnAt = time() + GameConfig.WaveDelay
end

function WaveService.GetCurrentWave()
	return currentWave
end

function WaveService.Start()
	if connection then
		return
	end
	startWave(1)
	-- One update connection owns all transitions and the active boss deadline.
	connection = RunService.Heartbeat:Connect(function()
		if pendingWave then
			if time() >= nextSpawnAt then
				local wave = pendingWave
				pendingWave = nil
				nextSpawnAt = nil
				startWave(wave)
			end
			return
		end

		local enemy = EnemyService.GetActiveEnemy()
		if not enemy then
			scheduleWave(currentWave + 1)
		elseif enemy.IsBoss and time() >= enemy.Deadline then
			if GameConfig.DebugLogging then
				print(string.format("[WaveService] Boss timed out; returning to Wave %d", currentWave - 1))
			end
			EnemyService.Remove()
			scheduleWave(currentWave - 1)
		elseif enemy.IsBoss then
			EnemyService.UpdateDisplay()
		end
	end)
end

return WaveService
