local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local State = require(script.Parent.CombatDebugState)
local EnemyService = require(script.Parent.EnemyService)
local ProgressionService = require(script.Parent.ProgressionService)
local Contexts = require(script.Parent.CombatContexts)
local WaveService = require(script.Parent.WaveService)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local CombatDebugService = {}
local started = false
local lastRequest, snapshots, playerConnections = {}, {}, {}

local function publish(player)
	local data = snapshots[player]
	if not data then return end
	local context = Contexts.Get(player)
	local enemy = context and EnemyService.GetActiveEnemy(context)
	data:SetAttribute("Active", context ~= nil)
	data:SetAttribute("Paused", State.IsPaused(player))
	data:SetAttribute("Wave", context and context.CurrentWave or 0)
	data:SetAttribute("EnemyHP", enemy and enemy.Health or 0)
	data:SetAttribute("EnemyMaxHP", enemy and enemy.MaxHealth or 0)
	data:SetAttribute("IsBoss", enemy ~= nil and enemy.IsBoss)
	data:SetAttribute("BossTimeRemaining", enemy and enemy.IsBoss and math.max(0, math.ceil(enemy.Deadline - time())) or 0)
	data:SetAttribute("OwnerUserId", player.UserId)
	data:SetAttribute("GoldMultiplier", ProgressionService.GetGoldMultiplier(player))
	data:SetAttribute("TotalDPS", player:GetAttribute("TotalDPS") or 0)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	data:SetAttribute("PlayerWalkSpeed", humanoid and humanoid.WalkSpeed or 16)
	for _, id in HeroConfig.HeroOrder do
		local folder = data[id]
		local progression = player:FindFirstChild("HeroProgression")
		local snapshot = progression and progression:FindFirstChild(id)
		for _, name in {"Owned", "Level", "Damage", "BossDamage", "AttackInterval", "AttackSpeed", "DPS", "AttackEnabled"} do
			local value = snapshot and snapshot:GetAttribute(name)
			if value == nil then
				if name == "Owned" or name == "AttackEnabled" then value = false else value = 0 end
			end
			folder:SetAttribute(name, value)
		end
		folder:SetAttribute("Selected", State.IsHeroSelected(player, id))
	end
end

function CombatDebugService.Start()
	if started or not State.IsAvailable() then return end
	started = true
	local remotes = Instance.new("Folder")
	remotes.Name = "IdleHeroSimulatorCombatDebug"
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Control"
	remote.Parent = remotes
	local function initializePlayer(player)
		if snapshots[player] then return end
		local data = Instance.new("Folder")
		data.Name = "IdleHeroSimulatorCombatDebug"
		for _, id in HeroConfig.HeroOrder do
			local folder = Instance.new("Folder")
			folder.Name = id
			folder.Parent = data
		end
		snapshots[player] = data
		playerConnections[player] = player:GetAttributeChangedSignal("CombatStatsRevision"):Connect(function() publish(player) end)
		local function speed(character)
			local function apply(humanoid)
				if player.Parent ~= Players or player.Character ~= character then return end
				local value = GameConfig.StudioTesting.PlayerWalkSpeed
				if State.IsAvailable() and type(value) == "number" and value > 0 and value < math.huge then humanoid.WalkSpeed = value end
				publish(player)
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then apply(humanoid) else
				local connection
				connection = character.ChildAdded:Connect(function(child)
					if child:IsA("Humanoid") then connection:Disconnect(); apply(child) end
				end)
			end
		end
		data:SetAttribute("PlayerWalkSpeed", 16)
		local connection = player.CharacterAdded:Connect(speed)
		data.Destroying:Connect(function() connection:Disconnect() end)
		if player.Character then speed(player.Character) end
		publish(player)
		data.Parent = player
	end
	Players.PlayerAdded:Connect(initializePlayer)
	Players.PlayerRemoving:Connect(function(player)
		if playerConnections[player] then playerConnections[player]:Disconnect(); playerConnections[player] = nil end
		if snapshots[player] then snapshots[player]:Destroy(); snapshots[player] = nil end
		lastRequest[player] = nil
	end)
	EnemyService.Changed:Connect(function(player, contextId)
		local context = Contexts.Get(player)
		if context and context.Id == contextId then publish(player) end
	end)
	Contexts.Changed:Connect(publish)
	State.Changed:Connect(publish)
	remote.OnServerEvent:Connect(function(player, ...)
		if not State.IsAvailable() or player.Parent ~= Players or not Contexts.Get(player) then return end
		local now = time()
		if lastRequest[player] and now - lastRequest[player] < 0.15 then return end
		lastRequest[player] = now
		local action, id, value = ...
		local count = select("#", ...)
		if action == "SetPaused" and count == 2 then
			State.SetPaused(player, id)
		elseif action == "SetHeroEnabled" and count == 3 then
			State.SetHeroEnabled(player, id, value)
		elseif action == "ResetHero" and count == 2 then
			ProgressionService.ResetHero(player, id)
		elseif action == "ResetEnemyHP" and count == 1 then
			EnemyService.ResetHealth(Contexts.Get(player))
		elseif action == "ResetWave" and count == 1 then
			WaveService.Reset(Contexts.Get(player))
			publish(player)
		end
	end)
	for _, player in Players:GetPlayers() do initializePlayer(player) end
	remotes.Parent = ReplicatedStorage
end
return CombatDebugService
