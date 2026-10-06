local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ProgressionMath = require(script.Parent.Parent.ProgressionMath)
local UpgradeEffects = require(script.Parent.Parent.UpgradeEffects)
local EconomyService = require(script.Parent.EconomyService)

local ProgressionService = {}
local playerHeroes = {}
local lastPurchaseAt = {}
local milestoneIndex = {}
local heroIds = {}
local combatOwner = nil
local started = false

local function validId(value)
	return type(value) == "string" and #value <= 64 and value:match("^[A-Za-z][A-Za-z0-9_]*$") ~= nil
end

local function validateConfig()
	for heroId in HeroConfig do
		local definition = ProgressionMath.GetHeroDefinition(heroId)
		if definition then
			assert(validId(heroId), "Invalid hero ID")
			table.insert(heroIds, heroId)
			milestoneIndex[heroId] = {}
			assert(ProgressionMath.IsValidAmount(definition.MaxLevel) and definition.MaxLevel >= 1, "Invalid maximum level")
			for _, upgrade in definition.Milestones or {} do
				assert(validId(upgrade.Id) and not milestoneIndex[heroId][upgrade.Id], "Invalid/duplicate upgrade ID")
				assert(type(upgrade.Name) == "string" and type(upgrade.Description) == "string", "Invalid upgrade text")
				assert(ProgressionMath.IsValidAmount(upgrade.Level) and upgrade.Level >= 1
					and upgrade.Level <= definition.MaxLevel, "Invalid milestone level")
				assert(ProgressionMath.IsValidAmount(upgrade.Cost), "Invalid milestone cost")
				local effect = upgrade.Effect
				assert(type(effect) == "table" and UpgradeEffects.IsSupported(effect.Type), "Unsupported upgrade effect")
				assert(type(effect.Value) == "number" and effect.Value > 0 and effect.Value < math.huge, "Invalid multiplier")
				if effect.Type == "SpecificHeroDamageMultiplier" then
					assert(ProgressionMath.GetHeroDefinition(effect.TargetHeroId), "Unknown target hero")
				end
				milestoneIndex[heroId][upgrade.Id] = upgrade
			end
		end
	end
	table.sort(heroIds)
	assert(ProgressionMath.GetHeroDefinition(HeroConfig.StartingHeroId), "Unknown starting hero")
end

local function getState(player, heroId)
	local heroes = playerHeroes[player]
	return heroes and heroes[heroId] or nil
end

function ProgressionService.GetHeroLevel(player, heroId)
	local state = getState(player, heroId)
	return state and state.Level or nil
end

function ProgressionService.GetHeroDamage(player, heroId, isBoss)
	local state = getState(player, heroId)
	return state and ProgressionMath.GetHeroDamage(heroId, state.Level,
		UpgradeEffects.Calculate(playerHeroes[player], heroId), isBoss) or nil
end

function ProgressionService.GetHeroAttackInterval(player, heroId)
	local state = getState(player, heroId)
	return state and ProgressionMath.GetAttackInterval(heroId,
		UpgradeEffects.Calculate(playerHeroes[player], heroId)) or nil
end

function ProgressionService.GetGoldMultiplier(player)
	local heroes = playerHeroes[player]
	return heroes and UpgradeEffects.Calculate(heroes, nil).Gold or 1
end

function ProgressionService.GetUpgradeState(player, heroId, upgradeId)
	local state = getState(player, heroId)
	local upgrade = milestoneIndex[heroId] and milestoneIndex[heroId][upgradeId]
	if not state or not upgrade then
		return nil
	end
	if state.Upgrades[upgradeId] then
		return "Purchased"
	end
	return state.Level >= upgrade.Level and "Available" or "Locked"
end

local function publish(player)
	local heroes = playerHeroes[player]
	player:SetAttribute("GoldMultiplier", ProgressionService.GetGoldMultiplier(player))
	for heroId, state in heroes do
		local definition = HeroConfig[heroId]
		local atMax = state.Level >= definition.MaxLevel
		local cost = atMax and 0 or ProgressionMath.GetHeroLevelCost(heroId, state.Level)
		local damage = ProgressionService.GetHeroDamage(player, heroId, false)
		state.Replicated:SetAttribute("Level", state.Level)
		state.Replicated:SetAttribute("Damage", damage)
		state.Replicated:SetAttribute("BossDamage", ProgressionService.GetHeroDamage(player, heroId, true))
		state.Replicated:SetAttribute("NextLevelCost", cost)
		state.Replicated:SetAttribute("AtMaxLevel", atMax)
		state.Replicated:SetAttribute("AttackInterval", ProgressionService.GetHeroAttackInterval(player, heroId))
		for upgradeId in milestoneIndex[heroId] do
			state.Replicated.Upgrades:SetAttribute(upgradeId,
				ProgressionService.GetUpgradeState(player, heroId, upgradeId))
		end
		-- Preserve the existing HUD/debug attributes without hero-specific logic.
		player:SetAttribute(heroId .. "Level", state.Level)
		player:SetAttribute(heroId .. "Damage", damage)
		player:SetAttribute(heroId .. "NextLevelCost", cost)
		player:SetAttribute(heroId .. "AtMaxLevel", atMax)
	end
end

local function setCombatOwner(player)
	combatOwner = player
	workspace:SetAttribute("HeroCombatOwnerUserId", player and player.UserId or 0)
	for _, currentPlayer in Players:GetPlayers() do
		currentPlayer:SetAttribute("IsHeroCombatOwner", currentPlayer == player)
	end
end

local function initializePlayer(player)
	if playerHeroes[player] then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "HeroProgression"
	local heroes = {}
	playerHeroes[player] = heroes
	for _, heroId in heroIds do
		local level = 1
		local testing = GameConfig.StudioTesting
		if RunService:IsStudio() and testing.Enabled then
			local requested = testing.StartingHeroLevels[heroId]
			if ProgressionMath.IsValidAmount(requested) and requested >= 1 then
				level = math.min(requested, HeroConfig[heroId].MaxLevel)
			end
		end
		local replicated = Instance.new("Folder")
		replicated.Name = heroId
		local upgrades = Instance.new("Folder")
		upgrades.Name = "Upgrades"
		upgrades.Parent = replicated
		replicated.Parent = folder
		heroes[heroId] = {Level = level, Upgrades = {}, Replicated = replicated}
	end
	publish(player)
	folder.Parent = player
	player:SetAttribute("IsHeroCombatOwner", player == combatOwner)
	if not combatOwner then
		setCombatOwner(player)
	end
end

function ProgressionService.GetCombatOwner()
	return combatOwner
end

local function beginPurchase(player)
	if not playerHeroes[player] or player.Parent ~= Players then
		return false, "InvalidPlayer"
	end
	local now = time()
	if lastPurchaseAt[player] and now - lastPurchaseAt[player] < GameConfig.Economy.PurchaseCooldown then
		return false, "TooFast"
	end
	lastPurchaseAt[player] = now
	return true
end

function ProgressionService.BuyHeroLevel(player, heroId)
	local allowed, reason = beginPurchase(player)
	if not allowed then
		return false, reason
	end
	if not validId(heroId) or not getState(player, heroId) then
		return false, "InvalidHero"
	end
	local state = getState(player, heroId)
	if state.Level >= HeroConfig[heroId].MaxLevel then
		return false, "MaxLevel"
	end
	local cost = ProgressionMath.GetHeroLevelCost(heroId, state.Level)
	-- Neither purchase path yields: spend and state change are one transaction.
	if not EconomyService.SpendGold(player, cost) then
		return false, "NotEnoughGold"
	end
	state.Level += 1
	publish(player)
	return true, "LevelPurchased"
end

function ProgressionService.BuyUpgrade(player, heroId, upgradeId)
	local allowed, reason = beginPurchase(player)
	if not allowed then
		return false, reason
	end
	if not validId(heroId) or not getState(player, heroId) then
		return false, "InvalidHero"
	end
	if not validId(upgradeId) or not milestoneIndex[heroId][upgradeId] then
		return false, "InvalidUpgrade"
	end
	local status = ProgressionService.GetUpgradeState(player, heroId, upgradeId)
	if status ~= "Available" then
		return false, status == "Purchased" and "AlreadyPurchased" or "Locked"
	end
	local upgrade = milestoneIndex[heroId][upgradeId]
	if not EconomyService.SpendGold(player, upgrade.Cost) then
		return false, "NotEnoughGold"
	end
	getState(player, heroId).Upgrades[upgradeId] = true
	publish(player) -- Refresh all heroes, including targets of global/cross-hero effects.
	return true, "UpgradePurchased"
end

function ProgressionService.Start()
	if started then
		return
	end
	validateConfig()
	started = true
	EconomyService.SetGoldMultiplierProvider(ProgressionService.GetGoldMultiplier)
	Players.PlayerAdded:Connect(initializePlayer)
	Players.PlayerRemoving:Connect(function(player)
		playerHeroes[player] = nil
		lastPurchaseAt[player] = nil
		local folder = player:FindFirstChild("HeroProgression")
		if folder then folder:Destroy() end
		if player == combatOwner then
			local replacement = nil
			for _, other in Players:GetPlayers() do
				if other ~= player and playerHeroes[other] then
					replacement = other
					break
				end
			end
			setCombatOwner(replacement)
		end
	end)
	for _, player in Players:GetPlayers() do
		initializePlayer(player)
	end

	local remotes = Instance.new("Folder")
	remotes.Name = "HeroCavesRemotes"
	local function remote(name, argumentCount, purchase)
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = remotes
		event.OnServerEvent:Connect(function(player, ...)
			if select("#", ...) ~= argumentCount then return end
			local success, reason = purchase(player, ...)
			if reason ~= "TooFast" then
				event:FireClient(player, success, reason)
			end
		end)
	end
	remote("BuyHeroLevel", 1, ProgressionService.BuyHeroLevel)
	remote("BuyUpgrade", 2, ProgressionService.BuyUpgrade)
	remotes.Parent = ReplicatedStorage
end

return ProgressionService
