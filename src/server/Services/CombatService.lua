local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local EnemyService = require(script.Parent.EnemyService)

local CombatService = {}

-- Server-only API. Captured target identity prevents hitting the next wave.
function CombatService.DamageEnemy(hero, target)
	if not hero or not hero.Model or not hero.Model.Parent
		or not target or target ~= EnemyService.GetActiveEnemy()
		or not target.Model.Parent or target.Health <= 0 then
		return false
	end
	local definition = HeroConfig[hero.Id]
	if not definition then
		return false
	end
	local body = target.Model.PrimaryPart
	local applied = EnemyService.Damage(definition.Damage)
	if applied and body and body.Parent then
		body.Color = HeroConfig.Impact.FlashColor
		local enemyDefinition = target.IsBoss and EnemyConfig.Boss or EnemyConfig.Normal
		TweenService:Create(body, TweenInfo.new(HeroConfig.Impact.FlashDuration), {
			Color = enemyDefinition.Color,
		}):Play()
	end
	return applied
end

return CombatService
