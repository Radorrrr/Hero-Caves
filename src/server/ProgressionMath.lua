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

local fixedModes = {x1 = 1, x10 = 10, x25 = 25, x100 = 100}

function ProgressionMath.IsPurchaseMode(mode)
	return type(mode) == "string" and (fixedModes[mode] ~= nil or mode == "MAX" or mode == "NEXT")
end

function ProgressionMath.GetNextMilestoneTarget(heroId, level)
	local hero = ProgressionMath.GetHeroDefinition(heroId)
	local target = nil
	for _, upgrade in hero.Milestones or {} do
		if upgrade.Level > level and upgrade.Level <= hero.MaxLevel
			and (not target or upgrade.Level < target) then target = upgrade.Level end
	end
	return target -- No later milestone: NEXT uses x1, bounded by MaxLevel.
end

function ProgressionMath.GetBulkLevelCost(heroId, level, count)
	local hero = ProgressionMath.GetHeroDefinition(heroId)
	local total = 0
	for offset = 0, math.min(count, math.max(0, hero.MaxLevel - level)) - 1 do
		total += ProgressionMath.GetHeroLevelCost(heroId, level + offset)
	end
	return total
end

function ProgressionMath.GetLevelPurchaseQuote(heroId, level, gold, mode)
	local hero = ProgressionMath.GetHeroDefinition(heroId)
	if not hero or not ProgressionMath.IsPurchaseMode(mode) then return nil end
	local target = mode == "NEXT" and ProgressionMath.GetNextMilestoneTarget(heroId, level) or nil
	local requested = fixedModes[mode] or (mode == "NEXT" and (target and target - level or 1))
		or math.max(0, hero.MaxLevel - level)
	requested = math.min(requested, math.max(0, hero.MaxLevel - level))
	local count, cost = 0, 0
	-- Each rounded level cost is summed exactly; stop at the first unaffordable step.
	for offset = 0, requested - 1 do
		local nextCost = ProgressionMath.GetHeroLevelCost(heroId, level + offset)
		if nextCost > gold - cost then break end
		count += 1
		cost += nextCost
	end
	return {Count = count, Cost = cost, Requested = requested, Target = target or 0}
end

return ProgressionMath
