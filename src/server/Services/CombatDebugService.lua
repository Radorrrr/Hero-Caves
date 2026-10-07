local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local State = require(script.Parent.CombatDebugState)
local EnemyService = require(script.Parent.EnemyService)
local ProgressionService = require(script.Parent.ProgressionService)

local CombatDebugService = {}
local started = false
local lastRequest = {}
local ownerConnection = nil

function CombatDebugService.Start()
	if started or not State.IsAvailable() then return end
	started = true
	local data = Instance.new("Folder")
	data.Name = "HeroCavesCombatDebug"
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Control"
	remote.Parent = data
	local function publish()
		local owner = ProgressionService.GetCombatOwner()
		local enemy = EnemyService.GetActiveEnemy()
		data:SetAttribute("Paused", State.IsPaused())
		data:SetAttribute("Wave", workspace:GetAttribute("HeroCavesWave") or 0)
		data:SetAttribute("EnemyHP", enemy and enemy.Health or 0)
		data:SetAttribute("EnemyMaxHP", enemy and enemy.MaxHealth or 0)
		data:SetAttribute("IsBoss", enemy ~= nil and enemy.IsBoss)
		data:SetAttribute("OwnerUserId", owner and owner.UserId or 0)
		data:SetAttribute("GoldMultiplier", owner and ProgressionService.GetGoldMultiplier(owner) or 1)
		data:SetAttribute("TotalDPS", owner and owner:GetAttribute("TotalDPS") or 0)
		for _, id in HeroConfig.HeroOrder do
			local folder = data:FindFirstChild(id)
			local snapshot = owner and owner:FindFirstChild("HeroProgression")
			snapshot = snapshot and snapshot:FindFirstChild(id)
			for _, name in {"Owned", "Level", "Damage", "BossDamage", "AttackInterval", "AttackSpeed", "DPS", "AttackEnabled"} do
				local value = snapshot and snapshot:GetAttribute(name)
				if value == nil then
					if name == "Owned" or name == "AttackEnabled" then value = false else value = 0 end
				end
				folder:SetAttribute(name, value)
			end
			folder:SetAttribute("Selected", State.IsHeroSelected(id))
		end
	end
	for _, id in HeroConfig.HeroOrder do
		local folder = Instance.new("Folder")
		folder.Name = id
		folder.Parent = data
	end
	local function watchOwner()
		if ownerConnection then ownerConnection:Disconnect(); ownerConnection = nil end
		local owner = ProgressionService.GetCombatOwner()
		if owner then
			-- Revision is published last, after the complete hero snapshot transaction.
			ownerConnection = owner:GetAttributeChangedSignal("CombatStatsRevision"):Connect(publish)
		end
		publish()
	end
	EnemyService.Changed:Connect(publish)
	State.Changed:Connect(publish)
	workspace:GetAttributeChangedSignal("HeroCavesWave"):Connect(publish)
	workspace:GetAttributeChangedSignal("HeroCombatOwnerUserId"):Connect(watchOwner)
	Players.PlayerRemoving:Connect(function(player) lastRequest[player] = nil end)
	remote.OnServerEvent:Connect(function(player, ...)
		if not State.IsAvailable() or player.Parent ~= Players then return end
		local now = time()
		if lastRequest[player] and now - lastRequest[player] < 0.15 then return end
		lastRequest[player] = now
		local action, id, value = ...
		local count = select("#", ...)
		if action == "SetPaused" and count == 2 then
			State.SetPaused(id)
		elseif action == "SetHeroEnabled" and count == 3 then
			State.SetHeroEnabled(id, value)
		elseif action == "ResetHero" and count == 2 then
			ProgressionService.ResetHero(ProgressionService.GetCombatOwner(), id)
		elseif action == "ResetEnemyHP" and count == 1 then
			EnemyService.ResetHealth()
		end
	end)
	watchOwner()
	data.Parent = ReplicatedStorage
end

return CombatDebugService
