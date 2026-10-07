local Players = game:GetService("Players")
local IslandService = require(script.Parent.IslandService)
local Contexts = require(script.Parent.CombatContexts)
local WaveService = require(script.Parent.WaveService)
local EnemyService = require(script.Parent.EnemyService)
local HeroService = require(script.Parent.HeroService)
local ProgressionService = require(script.Parent.ProgressionService)
local DebugState = require(script.Parent.CombatDebugState)
local CombatContextService = {}
local connections = {}
local started = false
function CombatContextService.GetContext(player)
	return Contexts.Get(player)
end
function CombatContextService.StopCombat(player, expectedIsland)
	local context = Contexts.GetStored(player)
	if not context or (expectedIsland and context.Island ~= expectedIsland) then return end
	Contexts.Invalidate(player)
	WaveService.Stop(context)
	HeroService.Stop(context)
	EnemyService.Remove(context)
	DebugState.Clear(player)
	context.Folder:Destroy()
	context.Folder, context.HeroFolder, context.EnemyFolder = nil, nil, nil
	context.Player, context.Island = nil, nil
	player:SetAttribute("IdleHeroesWave", 0)
end
function CombatContextService.StartCombat(player, island)
	if player.Parent ~= Players or IslandService.GetIsland(player) ~= island or island.Owner ~= player
		or not ProgressionService.GetHeroLevel(player, "Knight") then return nil end
	local existing = Contexts.GetStored(player)
	if existing then
		if Contexts.IsActive(existing) and existing.Island == island then return existing end
		CombatContextService.StopCombat(player)
	end
	local context = Contexts.Create(player, island)
	WaveService.Start(context)
	HeroService.Start(context)
	return context
end
function CombatContextService.Start()
	if started then return end
	started = true
	table.insert(connections, IslandService.Claimed:Connect(CombatContextService.StartCombat))
	table.insert(connections, IslandService.Releasing:Connect(CombatContextService.StopCombat))
	for _, player in Players:GetPlayers() do
		local island = IslandService.GetIsland(player)
		if island then CombatContextService.StartCombat(player, island) end
	end
end
function CombatContextService.Stop()
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	for player in Contexts.GetAll() do CombatContextService.StopCombat(player) end
	started = false
end
return CombatContextService
