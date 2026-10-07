local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ProgressionMath = require(script.Parent.Parent.ProgressionMath)
local EnemyService = require(script.Parent.EnemyService)

local Contexts = require(script.Parent.CombatContexts)

local EconomyService = {}
local Data = require(script.Parent.PlayerDataService)
local initialized = {}
local started = false
local goldAwarded = nil
local goldMultiplierProvider = function() return 1 end

local function initializePlayer(player)
 if not Data.IsReady(player) or initialized[player] then return end
 initialized[player] = true
 player:SetAttribute("Gold", Data.GetProfile(player).Data.Gold)
end

function EconomyService.GetGold(player)
 local profile = Data.IsReady(player) and Data.GetProfile(player)
 return profile and profile.Data.Gold or nil
end

function EconomyService.SetGoldMultiplierProvider(provider)
	assert(type(provider) == "function", "Gold multiplier provider must be a function")
	goldMultiplierProvider = provider
end

function EconomyService.EarnGold(player, baseAmount)
	if not ProgressionMath.IsValidAmount(baseAmount) then
		return false
	end
	local before = EconomyService.GetGold(player)
	if before == nil then return false end
	local success = EconomyService.AddGold(player,
		ProgressionMath.RoundValue(baseAmount * goldMultiplierProvider(player)))
	local awarded = EconomyService.GetGold(player) - before
	if success and awarded > 0 and goldAwarded then
		goldAwarded:FireClient(player, awarded)
	end
	return success, awarded
end

function EconomyService.CanAfford(player, amount)
	local gold = EconomyService.GetGold(player)
	return gold ~= nil and ProgressionMath.IsValidAmount(amount) and gold >= amount
end

function EconomyService.AddGold(player, amount)
	local gold = EconomyService.GetGold(player)
	if gold == nil or not ProgressionMath.IsValidAmount(amount) then
		return false
	end
	Data.GetProfile(player).Data.Gold = math.min(gold + amount, GameConfig.Economy.MaxGold)
	Data.MarkDirty(player)
	player:SetAttribute("Gold", EconomyService.GetGold(player))
	return true
end

function EconomyService.SpendGold(player, amount)
	if not EconomyService.CanAfford(player, amount) then
		return false
	end
	Data.GetProfile(player).Data.Gold -= amount
	Data.MarkDirty(player)
	player:SetAttribute("Gold", EconomyService.GetGold(player))
	return true
end

function EconomyService.Start()
	if started then
		return
	end
	started = true
	goldAwarded = Instance.new("RemoteEvent")
	goldAwarded.Name = "IdleHeroSimulatorGoldAwarded"
	goldAwarded.Parent = ReplicatedStorage
	Data.RegisterInitializer(initializePlayer)
	Players.PlayerAdded:Connect(initializePlayer)
	Players.PlayerRemoving:Connect(function(player)
		initialized[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		initializePlayer(player)
	end
	EnemyService.Defeated:Connect(function(player, contextId, enemySequence)
		local context = Contexts.Get(player)
		if not context or context.Id ~= contextId then return end
		local reward = context.PendingRewards[enemySequence]
		if reward == nil then return end
		-- Consume once before awarding: duplicates and old generations cannot pay out.
		context.PendingRewards[enemySequence] = nil
		EconomyService.EarnGold(player, reward)
	end)
end

return EconomyService
