local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

local function diagnostic(message, failed)
	if not RunService:IsStudio() then return end
	if failed then warn("[CombatContext] START FAILED: " .. message)
	else print("[CombatContext] " .. message) end
end

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
	table.clear(context.PendingRewards)
	DebugState.Clear(player)
	context.Folder:Destroy()
	context.Folder, context.HeroFolder, context.EnemyFolder = nil, nil, nil
	context.Player, context.Island = nil, nil
	player:SetAttribute("IdleHeroSimulatorWave", 0)
end

function CombatContextService.StartCombat(player, island)
	local function fail(reason)
		diagnostic((player and player.Name or "unknown player") .. ": " .. reason, true)
		return nil
	end
	if not player or player.Parent ~= Players then return fail("player is not present") end
	if not island or IslandService.GetIsland(player) ~= island or island.Owner ~= player then
		return fail("island is not the player's current authoritative ownership record")
	end
	if not ProgressionService.GetHeroLevel(player, "Knight") then return fail("progression is not initialized") end
	if not ProgressionService.OwnsHero(player, "Knight") then return fail("default Knight is not owned") end
	if not island.Model or not island.Model.Parent then return fail("runtime island Model is missing") end
	for _, name in {"EnemyPosition", "KnightSlot", "ArcherSlot", "MageSlot"} do
		local marker = island.Markers and island.Markers[name]
		if not marker or not marker:IsA("BasePart") or not marker:IsDescendantOf(island.Model) then
			return fail("missing/invalid runtime marker " .. name .. " on " .. island.Model.Name)
		end
	end
	local existing = Contexts.GetStored(player)
	if existing then
		if Contexts.IsActive(existing) and existing.Island == island then return existing end
		CombatContextService.StopCombat(player)
	end
	diagnostic("Runtime markers found on " .. island.Model.Name .. "; Knight owned = true")
	local context
	local success, reason = xpcall(function()
		context = Contexts.Create(player, island)
		diagnostic("Context created: " .. context.Id .. "; starting Wave 1")
		WaveService.Start(context)
		HeroService.Start(context)
		assert(context.CurrentEnemy and context.HeroesById.Knight, "Wave 1 enemy or Knight failed to spawn")
		-- Publish after successful physical startup as well as on registry changes.
		ProgressionService.Refresh(player)
	end, debug.traceback)
	if not success then
		CombatContextService.StopCombat(player)
		return fail(tostring(reason))
	end
	diagnostic(string.format("Enemy and Knight spawned: %s -> %s; active=%s; TotalDPS=%s",
		player.Name, island.Model.Name, tostring(player:GetAttribute("HasCombatArea")), tostring(player:GetAttribute("TotalDPS"))))
	return context
end

function CombatContextService.Start()
	if started then return end
	started = true
	-- Instances retain identity across BindableEvents; Lua ownership tables do not.
	table.insert(connections, IslandService.Claimed:Connect(function(player, islandModel)
		diagnostic("Claim received: " .. player.Name .. " -> " .. (islandModel and islandModel.Name or "missing Model"))
		local island = IslandService.GetIsland(player)
		if not island or island.Model ~= islandModel then
			diagnostic(player.Name .. ": claim Model does not match current ownership", true)
			return
		end
		CombatContextService.StartCombat(player, island)
	end))
	table.insert(connections, IslandService.Releasing:Connect(function(player, islandModel)
		local context = Contexts.GetStored(player)
		if context and context.Island.Model == islandModel then
			CombatContextService.StopCombat(player, context.Island)
		end
	end))
	diagnostic("Claim/release listeners ready; reconciling existing ownership")
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
