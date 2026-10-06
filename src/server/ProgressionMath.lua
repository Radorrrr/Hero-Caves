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

local function scaledInteger(base, growth, exponent, multiplier)
	local value = base * growth ^ exponent * (multiplier or 1)
	return math.floor(math.min(value, GameConfig.Economy.MaxGold) + 0.5)
end

function ProgressionMath.GetGoldReward(wave, isBoss)
	return scaledInteger(EnemyConfig.BaseGold, EnemyConfig.GoldGrowth, wave - 1,
		isBoss and EnemyConfig.BossGoldMultiplier or 1)
end

function ProgressionMath.GetKnightDamage(level)
	-- Future upgrade modifiers can be applied here before the final rounding.
	local knight = HeroConfig.Knight
	return scaledInteger(knight.BaseDamage, knight.DamageGrowth, level - 1)
end

function ProgressionMath.GetKnightLevelCost(level)
	local knight = HeroConfig.Knight
	return scaledInteger(knight.BaseLevelCost, knight.LevelCostGrowth, level - 1)
end

return ProgressionMath
