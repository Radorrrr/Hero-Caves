local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ProgressionMath = require(script.Parent.Parent.ProgressionMath)
local EnemyService = require(script.Parent.EnemyService)

local Contexts = require(script.Parent.CombatContexts)

local EconomyService = {}
local balances = {}
local started = false
local goldAwarded = nil
local goldMultiplierProvider = function() return 1 end

local function initializePlayer(player)
	if balances[player] == nil then
		local testing = GameConfig.StudioTesting
		local startingGold = 0
		if RunService:IsStudio() and testing.Enabled and ProgressionMath.IsValidAmount(testing.StartingGold) then
			startingGold = testing.StartingGold
		end
		balances[player] = startingGold
		player:SetAttribute("Gold", startingGold)
	end
end

function EconomyService.GetGold(player)
	return balances[player]
end

function EconomyService.SetGoldMultiplierProvider(provider)
	assert(type(provider) == "function", "Gold multiplier provider must be a function")
	goldMultiplierProvider = provider
end

function EconomyService.EarnGold(player, baseAmount)
	if not ProgressionMath.IsValidAmount(baseAmount) then
		return false
	end
	local before = balances[player]
	if before == nil then return false end
	local success = EconomyService.AddGold(player,
		ProgressionMath.RoundValue(baseAmount * goldMultiplierProvider(player)))
	local awarded = balances[player] - before
	if success and awarded > 0 and goldAwarded then
		goldAwarded:FireClient(player, awarded)
	end
	return success, awarded
end

function EconomyService.CanAfford(player, amount)
	local gold = balances[player]
	return gold ~= nil and ProgressionMath.IsValidAmount(amount) and gold >= amount
end

function EconomyService.AddGold(player, amount)
	local gold = balances[player]
	if gold == nil or not ProgressionMath.IsValidAmount(amount) then
		return false
	end
	balances[player] = math.min(gold + amount, GameConfig.Economy.MaxGold)
	player:SetAttribute("Gold", balances[player])
	return true
end

function EconomyService.SpendGold(player, amount)
	if not EconomyService.CanAfford(player, amount) then
		return false
	end
	balances[player] -= amount
	player:SetAttribute("Gold", balances[player])
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
	Players.PlayerAdded:Connect(initializePlayer)
	Players.PlayerRemoving:Connect(function(player)
		balances[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		initializePlayer(player)
	end
	EnemyService.Defeated:Connect(function(enemy)
		if enemy.RewardGranted then
			return
		end
		enemy.RewardGranted = true
		local context = enemy.Context
		if Contexts.IsActive(context) then
			EconomyService.EarnGold(context.Player, enemy.GoldReward)
		end
	end)
end

return EconomyService
