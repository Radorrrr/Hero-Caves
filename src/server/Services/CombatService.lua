local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EnemyService = require(script.Parent.EnemyService)

local CombatService = {}
local connection = nil

function CombatService.Start()
	if connection or not GameConfig.TestAttackerEnabled then
		return
	end
	assert(GameConfig.TestAttackInterval > 0, "TestAttackInterval must be positive")
	local nextAttackAt = time() + GameConfig.TestAttackInterval
	connection = RunService.Heartbeat:Connect(function()
		if time() >= nextAttackAt then
			-- No catch-up bursts after a long frame.
			nextAttackAt = time() + GameConfig.TestAttackInterval
			EnemyService.Damage(GameConfig.TestDamage)
		end
	end)
end

function CombatService.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return CombatService
