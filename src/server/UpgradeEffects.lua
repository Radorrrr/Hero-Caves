local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)

local UpgradeEffects = {}
local supported = {
	HeroDamageMultiplier = true,
	GoldMultiplier = true,
	AttackSpeedMultiplier = true,
	GlobalHeroDamageMultiplier = true,
	BossDamageMultiplier = true,
	SpecificHeroDamageMultiplier = true,
}

function UpgradeEffects.IsSupported(effectType)
	return supported[effectType] == true
end

-- States and purchased IDs are private server data; base config is never mutated.
function UpgradeEffects.Calculate(heroStates, targetHeroId)
	local result = {HeroDamage = 1, GlobalDamage = 1, SpecificDamage = 1,
		BossDamage = 1, AttackSpeed = 1, Gold = 1}
	for sourceHeroId, state in heroStates do
		local definition = HeroConfig[sourceHeroId]
		for _, upgrade in definition.Milestones or {} do
			if state.Owned and state.Upgrades[upgrade.Id] then
				local effect = upgrade.Effect
				local value = effect.Value
				if effect.Type == "HeroDamageMultiplier" and sourceHeroId == targetHeroId then
					result.HeroDamage *= value
				elseif effect.Type == "GlobalHeroDamageMultiplier" then
					result.GlobalDamage *= value
				elseif effect.Type == "SpecificHeroDamageMultiplier" and effect.TargetHeroId == targetHeroId then
					result.SpecificDamage *= value
				elseif effect.Type == "BossDamageMultiplier" and sourceHeroId == targetHeroId then
					result.BossDamage *= value
				elseif effect.Type == "AttackSpeedMultiplier" and sourceHeroId == targetHeroId then
					result.AttackSpeed *= value
				elseif effect.Type == "GoldMultiplier" then
					result.Gold *= value
				end
			end
		end
	end
	return result
end

return UpgradeEffects
