local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ProgressionMath = require(script.Parent.Parent.ProgressionMath)
local EnemyService = require(script.Parent.EnemyService)

local EconomyService = {}
local balances = {}
local started = false

local function initializePlayer(player)
	if balances[player] == nil then
		balances[player] = 0
		player:SetAttribute("Gold", 0)
	end
end

function EconomyService.GetGold(player)
	return balances[player]
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
		-- Shared encounter prototype: each present player receives their own reward.
		for _, player in Players:GetPlayers() do
			EconomyService.AddGold(player, enemy.GoldReward)
		end
	end)
end

return EconomyService
