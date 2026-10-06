local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local ProgressionMath = {}

function ProgressionMath.IsValidAmount(value)
	return type(value) == "number" and value == value
		and value >= 0 and value <= GameConfig.Economy.MaxGold
		and value == math.floor(value)
end

function ProgressionMath.GetHeroDefinition(heroId)
	if type(heroId) ~= "string" then
		return nil
	end
	local definition = HeroConfig[heroId]
	return type(definition) == "table" and definition.BaseDamage and definition or nil
end

function ProgressionMath.RoundValue(value)
	return math.floor(math.min(value, GameConfig.Economy.MaxGold) + 0.5)
end

function ProgressionMath.GetGoldReward(wave, isBoss)
	return ProgressionMath.RoundValue(EnemyConfig.BaseGold * EnemyConfig.GoldGrowth ^ (wave - 1)
		* (isBoss and EnemyConfig.BossGoldMultiplier or 1))
end

function ProgressionMath.GetHeroDamage(heroId, level, effects, isBoss)
	local hero = ProgressionMath.GetHeroDefinition(heroId)
	local value = hero.BaseDamage * hero.DamageGrowth ^ (level - 1)
	if effects then
		value *= effects.HeroDamage * effects.GlobalDamage * effects.SpecificDamage
		if isBoss then
			value *= effects.BossDamage
		end
	end
	return ProgressionMath.RoundValue(value)
end

function ProgressionMath.GetHeroLevelCost(heroId, level)
	local hero = ProgressionMath.GetHeroDefinition(heroId)
	return ProgressionMath.RoundValue(hero.BaseLevelCost * hero.LevelCostGrowth ^ (level - 1))
end

function ProgressionMath.GetAttackInterval(heroId, effects)
	local hero = ProgressionMath.GetHeroDefinition(heroId)
	return hero.AttackInterval / (effects and effects.AttackSpeed or 1)
end

return ProgressionMath
