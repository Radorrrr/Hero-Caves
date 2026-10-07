local Players = game:GetService("Players")
local CombatContexts = {}
local contexts = {}
local serial = 0
local changed = Instance.new("BindableEvent")
CombatContexts.Changed = changed.Event

function CombatContexts.IsActive(context)
	return context ~= nil and context.Active == true and contexts[context.Player] == context
		and context.Player.Parent == Players and context.Island.Owner == context.Player
end

function CombatContexts.Get(player)
	local context = contexts[player]
	return CombatContexts.IsActive(context) and context or nil
end

function CombatContexts.GetStored(player)
	return contexts[player]
end

function CombatContexts.GetAll()
	return table.clone(contexts)
end

function CombatContexts.Create(player, island)
	assert(not contexts[player], "Combat context already exists")
	serial += 1
	local folder = Instance.new("Folder")
	folder.Name = "Combat"
	folder:SetAttribute("OwnerUserId", player.UserId)
	folder:SetAttribute("ContextId", tostring(player.UserId) .. ":" .. serial)
	folder.Parent = island.Model
	local function child(name)
		local obj = Instance.new("Folder")
		obj.Name = name
		obj.Parent = folder
		return obj
	end
	local context = {Player = player, Island = island, Active = true,
		Id = folder:GetAttribute("ContextId"), Folder = folder,
		EnemyFolder = child("Enemies"), HeroFolder = child("Heroes"),
		CurrentWave = 0, CurrentEnemy = nil, EnemySequence = 0,
		Heroes = {}, HeroesById = {}, HeroConnections = {}, PendingRewards = {}}
	contexts[player] = context
	changed:Fire(player)
	return context
end

function CombatContexts.Invalidate(player)
	local context = contexts[player]
	if not context then return nil end
	context.Active = false -- Invalidate every captured target before any cleanup.
	contexts[player] = nil
	changed:Fire(player)
	return context
end

return CombatContexts
