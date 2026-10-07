-- Paste into the SERVER Command Bar in a two-client Studio session, BEFORE claiming.
-- Use defaults: StudioTesting disabled, Knight level 1, attacks enabled.
-- Observes the actual ClaimZone -> IslandService BindableEvent path; does not force claims.
assert(game:GetService("RunService"):IsStudio(), "Studio-only verification")
local services = game:GetService("ServerScriptService").Server.Services
local islands = require(services.IslandService)
local combat = require(services.CombatContextService)
local model = workspace.IdleHeroSimulatorWorld.Islands.Island1
local source = {Model = model, Nested = {Player = game:GetService("Players"):GetPlayers()[1]}}
local probe = Instance.new("BindableEvent")
local received
probe.Event:Connect(function(value) received = value end)
probe:Fire(source)
task.delay(0.1, function()
	assert(received and received ~= source and received.Nested ~= source.Nested,
		"Real Roblox BindableEvent must copy the Lua argument table")
	assert(received.Model == model and received.Nested.Player == source.Nested.Player,
		"Instances must retain identity through BindableEvent")
	probe:Destroy()
	print("[Studio regression] Real BindableEvent copying and Instance identity verified")
end)

local verified = {}
local connection
connection = islands.Claimed:Connect(function(player, islandModel)
	assert(typeof(islandModel) == "Instance" and islandModel:IsA("Model"), "Claim payload must be a Model")
	task.delay(0.1, function()
		local island = islands.GetIsland(player)
		local context = combat.GetContext(player)
		assert(island and island.Model == islandModel, "Claim must resolve actual ownership")
		assert(context and context.Player == player and context.Island == island, "Missing authoritative context")
		assert(context.CurrentWave == 1 and context.CurrentEnemy, "Missing Wave 1 enemy")
		local knight = context.HeroesById.Knight
		assert(knight and knight.Owner == player, "Missing default owned Knight")
		assert((knight.Model.PrimaryPart.Position - island.Markers.KnightSlot.Position).Magnitude < 0.01)
		assert((context.CurrentEnemy.Model.PrimaryPart.Position - island.Markers.EnemyPosition.Position).Magnitude < 0.01)
		assert(player:GetAttribute("HasCombatArea") == true, "Active state was not published")
		assert(math.abs(player:GetAttribute("TotalDPS") - 20 / 1.3) < 0.001, "Wrong default TotalDPS")
		for other, otherContext in verified do
			assert(other ~= player and otherContext ~= context, "Duplicate verification or shared context")
			assert(otherContext.CurrentEnemy ~= context.CurrentEnemy, "Shared enemy")
		end
		verified[player] = context
		print("[Studio regression] PASS: " .. player.Name .. " -> " .. islandModel.Name .. " -> " .. context.Id)
		local count = 0
		for _ in verified do count += 1 end
		if count == 2 then
			connection:Disconnect()
			print("[Studio regression] PASS: both actual claims started separate combat; check each client HUD")
		end
	end)
end)
task.delay(120, function() connection:Disconnect() end)
print("[Studio regression] Ready: claim Island 1 in client A, then Island 2 in client B within 120 seconds")
