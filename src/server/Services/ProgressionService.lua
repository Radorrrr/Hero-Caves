local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ProgressionMath = require(script.Parent.Parent.ProgressionMath)
local EconomyService = require(script.Parent.EconomyService)

local ProgressionService = {}
local levels = {}
local lastPurchaseAt = {}
local combatOwner = nil
local started = false

local function publish(player)
	local level = levels[player]
	local atMax = level >= HeroConfig.Knight.MaxLevel
	player:SetAttribute("KnightLevel", level)
	player:SetAttribute("KnightDamage", ProgressionMath.GetKnightDamage(level))
	player:SetAttribute("KnightNextLevelCost", atMax and 0 or ProgressionMath.GetKnightLevelCost(level))
	player:SetAttribute("KnightAtMaxLevel", atMax)
end

local function setCombatOwner(player)
	combatOwner = player
	workspace:SetAttribute("KnightCombatOwnerUserId", player and player.UserId or 0)
	for _, currentPlayer in Players:GetPlayers() do
		currentPlayer:SetAttribute("IsKnightCombatOwner", currentPlayer == player)
	end
end

local function initializePlayer(player)
	if levels[player] then
		return
	end
	levels[player] = 1
	publish(player)
	player:SetAttribute("IsKnightCombatOwner", player == combatOwner)
	if not combatOwner then
		setCombatOwner(player)
	end
end

function ProgressionService.GetKnightLevel(player)
	return levels[player]
end

function ProgressionService.GetKnightDamage(player)
	local level = levels[player]
	return level and ProgressionMath.GetKnightDamage(level) or nil
end

function ProgressionService.GetCombatOwner()
	return combatOwner
end

function ProgressionService.BuyKnightLevel(player)
	local level = levels[player]
	if not level or player.Parent ~= Players then
		return false, "InvalidPlayer"
	end
	local now = time()
	if lastPurchaseAt[player] and now - lastPurchaseAt[player] < GameConfig.Economy.PurchaseCooldown then
		return false, "TooFast"
	end
	lastPurchaseAt[player] = now
	if level >= HeroConfig.Knight.MaxLevel then
		return false, "MaxLevel"
	end
	local cost = ProgressionMath.GetKnightLevelCost(level)
	-- This transaction never yields: concurrent requests cannot spend the same gold.
	if not EconomyService.SpendGold(player, cost) then
		return false, "NotEnoughGold"
	end
	levels[player] = level + 1
	publish(player)
	return true, "Purchased"
end

function ProgressionService.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(initializePlayer)
	Players.PlayerRemoving:Connect(function(player)
		levels[player] = nil
		lastPurchaseAt[player] = nil
		if player == combatOwner then
			local replacement = nil
			for _, other in Players:GetPlayers() do
				if other ~= player and levels[other] then
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
	local buyLevel = Instance.new("RemoteEvent")
	buyLevel.Name = "BuyKnightLevel"
	buyLevel.Parent = remotes
	buyLevel.OnServerEvent:Connect(function(player, ...)
		-- The client sends no price, damage, level or other payload.
		if select("#", ...) ~= 0 then
			return
		end
		local success, reason = ProgressionService.BuyKnightLevel(player)
		if reason ~= "TooFast" then
			buyLevel:FireClient(player, success, reason)
		end
	end)
	remotes.Parent = ReplicatedStorage
end

return ProgressionService
