local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ProgressionMath = require(script.Parent.Parent.ProgressionMath)
local UpgradeEffects = require(script.Parent.Parent.UpgradeEffects)
local EconomyService = require(script.Parent.EconomyService)

local CombatDebugState = require(script.Parent.CombatDebugState)
local Contexts = require(script.Parent.CombatContexts)

local ProgressionService = {}
local playerHeroes = {}
local resetEvent = Instance.new("BindableEvent")
ProgressionService.HeroReset = resetEvent.Event
local ownedEvent = Instance.new("BindableEvent")
ProgressionService.HeroOwned = ownedEvent.Event
local goldConnections = {}
local purchaseModes = {"x1", "x10", "x25", "x100", "MAX", "NEXT"}
local lastPurchaseAt = {}
local milestoneIndex = {}
local heroIds = {}
local started = false

local function validId(value)
	return type(value) == "string" and #value <= 64 and value:match("^[A-Za-z][A-Za-z0-9_]*$") ~= nil
end

local function validateConfig()
	for heroId in HeroConfig do
		local definition = ProgressionMath.GetHeroDefinition(heroId)
		if definition then
			assert(validId(heroId), "Invalid hero ID")
			assert(definition.HeroId == heroId, "HeroId must match its config key")
			assert(ProgressionMath.IsValidAmount(definition.UnlockCost), "Invalid hero unlock cost")
			assert(type(definition.OwnedByDefault) == "boolean", "Missing default ownership")
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
	local ordered = {}
	for _, id in HeroConfig.HeroOrder do
		assert(ProgressionMath.GetHeroDefinition(id) and not ordered[id], "Invalid/duplicate hero order")
		ordered[id] = true
	end
	for _, id in heroIds do assert(ordered[id], "Hero missing from discovery order") end
end

local function getState(player, heroId)
	local heroes = playerHeroes[player]
	return heroes and heroes[heroId] or nil
end

function ProgressionService.GetHeroLevel(player, heroId)
	local state = getState(player, heroId)
	return state and state.Level or nil
end

function ProgressionService.OwnsHero(player, heroId)
	local state = getState(player, heroId)
	return state ~= nil and state.Owned == true
end

function ProgressionService.GetHeroDamage(player, heroId, isBoss)
	local state = getState(player, heroId)
	return state and state.Owned and ProgressionMath.GetHeroDamage(heroId, state.Level,
		UpgradeEffects.Calculate(playerHeroes[player], heroId), isBoss) or nil
end

function ProgressionService.GetHeroAttackInterval(player, heroId)
	local state = getState(player, heroId)
	return state and state.Owned and ProgressionMath.GetAttackInterval(heroId,
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
	if not state.Owned then
		return "Locked"
	end
	if state.Upgrades[upgradeId] then
		return "Purchased"
	end
	return state.Level >= upgrade.Level and "Available" or "Locked"
end

local function publishPurchaseQuotes(player)
	local heroes = playerHeroes[player]
	if not heroes then return end
	for heroId, state in heroes do
		for _, mode in purchaseModes do
			local quote = ProgressionMath.GetLevelPurchaseQuote(heroId, state.Level,
				state.Owned and (EconomyService.GetGold(player) or 0) or 0, mode)
			local folder = state.Replicated.PurchaseModes[mode]
			folder:SetAttribute("Count", state.Owned and quote.Count or 0)
			folder:SetAttribute("Cost", state.Owned and quote.Cost or 0)
			folder:SetAttribute("Requested", quote.Requested)
			folder:SetAttribute("Target", quote.Target)
		end
	end
end

local function publish(player)
	local heroes = playerHeroes[player]
	if not heroes then return end
	player:SetAttribute("HasCombatArea", Contexts.Get(player) ~= nil)
	player:SetAttribute("GoldMultiplier", ProgressionService.GetGoldMultiplier(player))
	local totalDPS = 0
	for heroId, state in heroes do
		local definition = HeroConfig[heroId]
		local atMax = state.Level >= definition.MaxLevel
		local cost = atMax and 0 or ProgressionMath.GetHeroLevelCost(heroId, state.Level)
		local damage = ProgressionService.GetHeroDamage(player, heroId, false) or 0
		state.Replicated:SetAttribute("Owned", state.Owned)
		state.Replicated:SetAttribute("UnlockCost", definition.UnlockCost)
		state.Replicated:SetAttribute("Level", state.Level)
		state.Replicated:SetAttribute("Damage", damage)
		state.Replicated:SetAttribute("BossDamage", ProgressionService.GetHeroDamage(player, heroId, true) or 0)
		state.Replicated:SetAttribute("NextLevelCost", cost)
		state.Replicated:SetAttribute("AtMaxLevel", atMax)
		local interval = ProgressionService.GetHeroAttackInterval(player, heroId) or 0
		local speed = interval > 0 and 1 / interval or 0
		local dps = damage * speed
		state.Replicated:SetAttribute("AttackInterval", interval)
		state.Replicated:SetAttribute("AttackSpeed", speed)
		state.Replicated:SetAttribute("DPS", dps)
		local attackEnabled = state.Owned and Contexts.Get(player) ~= nil and CombatDebugState.IsHeroEnabled(player, heroId)
		state.Replicated:SetAttribute("AttackEnabled", attackEnabled)
		if attackEnabled then totalDPS += dps end
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
	publishPurchaseQuotes(player)
	player:SetAttribute("TotalDPS", totalDPS)
	player:SetAttribute("CombatStatsRevision", (player:GetAttribute("CombatStatsRevision") or 0) + 1)
end

local function startingLevel(heroId)
	local testing = GameConfig.StudioTesting
	local requested = RunService:IsStudio() and testing.Enabled and testing.StartingHeroLevels[heroId]
	if ProgressionMath.IsValidAmount(requested) and requested >= 1 then
		return math.min(requested, HeroConfig[heroId].MaxLevel)
	end
	return 1
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
		local testing = GameConfig.StudioTesting
		local owned = HeroConfig[heroId].OwnedByDefault
			or (RunService:IsStudio() and testing.Enabled and testing.StartingOwnedHeroes[heroId] == true)
		local replicated = Instance.new("Folder")
		replicated.Name = heroId
		local upgrades = Instance.new("Folder")
		upgrades.Name = "Upgrades"
		upgrades.Parent = replicated
		local quotes = Instance.new("Folder")
		quotes.Name = "PurchaseModes"
		for _, mode in purchaseModes do
			local quote = Instance.new("Folder")
			quote.Name = mode
			quote.Parent = quotes
		end
		quotes.Parent = replicated
		replicated.Parent = folder
		heroes[heroId] = {Owned = owned, Level = owned and startingLevel(heroId) or 1,
			Upgrades = {}, Replicated = replicated}
	end
	publish(player)
	goldConnections[player] = player:GetAttributeChangedSignal("Gold"):Connect(function()
		publishPurchaseQuotes(player)
	end)
	folder.Parent = player
end

function ProgressionService.Refresh(player)
	publish(player)
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

function ProgressionService.BuyHeroLevels(player, heroId, mode)
	local allowed, reason = beginPurchase(player)
	if not allowed then return false, reason end
	if not validId(heroId) or not getState(player, heroId) then return false, "InvalidHero" end
	if not ProgressionMath.IsPurchaseMode(mode) then return false, "InvalidMode" end
	local state = getState(player, heroId)
	if not state.Owned then return false, "NotOwned" end
	if state.Level >= HeroConfig[heroId].MaxLevel then return false, "MaxLevel" end
	local quote = ProgressionMath.GetLevelPurchaseQuote(heroId, state.Level, EconomyService.GetGold(player), mode)
	if quote.Count == 0 or not EconomyService.SpendGold(player, quote.Cost) then
		return false, "NotEnoughGold"
	end
	-- One transaction, one state update, one stat refresh; no per-level remote calls.
	state.Level += quote.Count
	publish(player)
	return true, "LevelPurchased", quote.Count, quote.Cost
end

function ProgressionService.BuyHeroLevel(player, heroId)
	return ProgressionService.BuyHeroLevels(player, heroId, "x1")
end

function ProgressionService.ResetHero(player, heroId)
	if not CombatDebugState.IsAvailable() or not Contexts.Get(player) or not playerHeroes[player] or player.Parent ~= Players
		or not validId(heroId) then return false end
	local state = getState(player, heroId)
	if not state then return false end
	state.Level = 1
	table.clear(state.Upgrades)
	-- Ownership, gold, other hero progress, wave and enemy are untouched.
	resetEvent:Fire(player, heroId)
	publish(player)
	return true
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
	if not ProgressionService.OwnsHero(player, heroId) then
		return false, "NotOwned"
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

-- Private ownership, never replicated display attributes, controls discovery.
function ProgressionService.GetNextHero(player)
	if not playerHeroes[player] then return nil end
	for _, id in HeroConfig.HeroOrder do
		if not ProgressionService.OwnsHero(player, id) then return id end
	end
	return nil
end

function ProgressionService.PurchaseNextHero(player)
	local allowed, reason = beginPurchase(player)
	if not allowed then return false, reason end
	local heroId = ProgressionService.GetNextHero(player)
	if not heroId then return false, "AllHeroesOwned" end
	if not EconomyService.SpendGold(player, HeroConfig[heroId].UnlockCost) then
		return false, "NotEnoughGold"
	end
	local state = getState(player, heroId)
	state.Owned = true
	state.Level = startingLevel(heroId)
	publish(player)
	ownedEvent:Fire(player, heroId) -- Stable Instance and ID, not a mutable ownership table.
	return true, "HeroPurchased", heroId
end

function ProgressionService.Start()
	if started then
		return
	end
	validateConfig()
	started = true
	CombatDebugState.Changed:Connect(publish)
	Contexts.Changed:Connect(publish)
	EconomyService.SetGoldMultiplierProvider(ProgressionService.GetGoldMultiplier)
	Players.PlayerAdded:Connect(initializePlayer)
	Players.PlayerRemoving:Connect(function(player)
		if goldConnections[player] then goldConnections[player]:Disconnect(); goldConnections[player] = nil end
		playerHeroes[player] = nil
		lastPurchaseAt[player] = nil
		local folder = player:FindFirstChild("HeroProgression")
		if folder then folder:Destroy() end

	end)
	for _, player in Players:GetPlayers() do
		initializePlayer(player)
	end

	local remotes = Instance.new("Folder")
	remotes.Name = "IdleHeroSimulatorRemotes"
	local function remote(name, argumentCount, purchase)
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = remotes
		event.OnServerEvent:Connect(function(player, ...)
			if select("#", ...) ~= argumentCount then return end
			local success, reason, count, cost = purchase(player, ...)
			if reason ~= "TooFast" then
				event:FireClient(player, success, reason, count, cost)
			end
		end)
	end
	remote("BuyHeroLevels", 2, ProgressionService.BuyHeroLevels)
	remote("BuyHeroLevel", 1, ProgressionService.BuyHeroLevel)
	remote("BuyUpgrade", 2, ProgressionService.BuyUpgrade)
	remotes.Parent = ReplicatedStorage
end

return ProgressionService
