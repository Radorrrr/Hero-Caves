local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.WorldConfig)

local IslandService = {}
local islands = {}
local playerIslands = {}
local playerConnections = {}
local connections = {}
local lastFeedback = {}
local world, hubSpawn, feedback
local started = false
local generation = 0

local function part(class, name, size, frame, parent, color)
	local object = Instance.new(class)
	object.Name = name
	object.Size = size
	object.CFrame = frame
	object.Anchored = true
	object.CanCollide = true
	object.Color = color or Color3.fromRGB(80, 105, 100)
	object.Material = Enum.Material.SmoothPlastic
	object.Parent = parent
	return object
end

local function marker(name, frame, parent)
	local object = part("Part", name, Vector3.new(1, 1, 1), frame, parent)
	object.Transparency = 1
	object.CanCollide = false
	object.CanTouch = false
	object.CanQuery = false
	return object
end

local function spawnPoint(name, frame, parent)
	local spawn = part("SpawnLocation", name, Vector3.new(8, 1, 8), frame, parent,
		Color3.fromRGB(90, 165, 195))
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Enabled = true
	return spawn
end

local function sign(anchor, text)
	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnershipDisplay"
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(300, 60)
	gui.StudsOffset = Vector3.new(0, 7, 0)
	gui.AlwaysOnTop = true
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Name = "Owner"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.TextWrapped = true
	label.Text = text
	label.Parent = gui
	return label
end

local function showFeedback(player, message)
	local now = time()
	if lastFeedback[player] and now - lastFeedback[player] < Config.ClaimFeedbackCooldown then return end
	lastFeedback[player] = now
	feedback:FireClient(player, message)
end

local function cave(island)
	local model = Instance.new("Model")
	model.Name = "CavePlaceholder"
	local origin = island.Markers.CavePosition.CFrame
	local color = Color3.fromRGB(75, 75, 85)
	part("Part", "Left", Vector3.new(4, 12, 12), origin * CFrame.new(-7, 6, 0), model, color)
	part("Part", "Right", Vector3.new(4, 12, 12), origin * CFrame.new(7, 6, 0), model, color)
	part("Part", "Roof", Vector3.new(18, 4, 12), origin * CFrame.new(0, 12, 0), model, color)
	part("Part", "Back", Vector3.new(18, 12, 2), origin * CFrame.new(0, 6, 5), model, color)
	model.Parent = island.Model
	return model
end

function IslandService.GetIsland(player)
	return playerIslands[player]
end

function IslandService.GetIslandOwner(islandId)
	local island = islands[islandId]
	return island and island.Owner or nil
end

function IslandService.GetSpawnLocation(player)
	local island = playerIslands[player]
	return island and island.Markers.PlayerSpawn or hubSpawn
end

local function insideZone(player, island)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return false end
	local point = island.Markers.ClaimZone.CFrame:PointToObjectSpace(root.Position)
	local half = island.Markers.ClaimZone.Size / 2
	return math.abs(point.X) <= half.X and math.abs(point.Y) <= half.Y
		and math.abs(point.Z) <= half.Z
end

-- Server-only entry point; no ownership-request remote exists.
function IslandService.TryClaim(player, islandId)
	local island = islands[islandId]
	if not started or not island or not player or player.Parent ~= Players or not insideZone(player, island) then
		return false, "InvalidClaim"
	end
	local existing = playerIslands[player]
	if existing then
		if existing ~= island then showFeedback(player, "You already own Island " .. existing.Id .. ".") end
		return false, "AlreadyOwnsIsland"
	end
	if island.Owner then
		local full = true
		for _, current in islands do if not current.Owner then full = false; break end end
		showFeedback(player, full and "All islands are occupied. Wait in the Hub."
			or "This island is occupied. Choose an UNCLAIMED island.")
		return false, "Occupied"
	end
	-- Checks and both ownership writes never yield: only the first claim can win.
	island.Owner = player
	playerIslands[player] = island
	island.Model:SetAttribute("OwnerUserId", player.UserId)
	player:SetAttribute("IslandId", island.Id)
	player.RespawnLocation = island.Markers.PlayerSpawn
	island.Label.Text = player.DisplayName .. "'s Cave"
	island.Markers.ClaimZone.Color = Color3.fromRGB(80, 175, 105)
	island.Cave = cave(island)
	showFeedback(player, "Island " .. island.Id .. " claimed. This is your cave.")
	return true, "Claimed"
end

local function release(player)
	local island = playerIslands[player]
	if island then
		island.Owner = nil
		playerIslands[player] = nil
		island.Model:SetAttribute("OwnerUserId", 0)
		island.Label.Text = "UNCLAIMED"
		island.Markers.ClaimZone.Color = Color3.fromRGB(240, 200, 90)
		if island.Cave then island.Cave:Destroy(); island.Cave = nil end
	end
	player:SetAttribute("IslandId", nil)
	lastFeedback[player] = nil
	if playerConnections[player] then playerConnections[player]:Disconnect(); playerConnections[player] = nil end
	player.RespawnLocation = nil
end

local function registerPlayer(player)
	if playerConnections[player] then return end
	player:SetAttribute("IslandId", nil)
	player.RespawnLocation = hubSpawn
	local currentGeneration = generation
	local function positionCharacter(character)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root or not started or generation ~= currentGeneration
			or player.Parent ~= Players or player.Character ~= character then return end
		local spawn = IslandService.GetSpawnLocation(player)
		if spawn then character:PivotTo(spawn.CFrame * CFrame.new(0, 3, 0)) end
	end
	playerConnections[player] = player.CharacterAdded:Connect(positionCharacter)
	if player.Character then task.spawn(positionCharacter, player.Character) end
end

function IslandService.Start()
	if started then return end
	assert(Config.IslandCount >= 1 and Config.IslandCount % 1 == 0, "Invalid island count")
	assert(Config.IslandRadius > Config.HubSize.X / 2 + Config.IslandSize.Z / 2, "Islands must be outside Hub")
	assert(not workspace:FindFirstChild(Config.FolderName), "World folder already exists")
	generation += 1
	world = Instance.new("Folder")
	world.Name = Config.FolderName
	world.Parent = workspace
	local hub = Instance.new("Model")
	hub.Name = "Hub"
	hub.Parent = world
	local hubFrame = CFrame.new(Config.HubPosition)
	part("Part", "Platform", Config.HubSize, hubFrame, hub, Color3.fromRGB(90, 110, 145))
	local surface = Config.HubPosition + Vector3.new(0, Config.HubSize.Y / 2, 0)
	hubSpawn = spawnPoint("PlayerSpawn", CFrame.new(surface + Config.HubSpawnOffset), hub)
	sign(hubSpawn, "HERO CAVES · HUB")
	local folder = Instance.new("Folder")
	folder.Name = "Islands"
	folder.Parent = world
	local bridges = Instance.new("Folder")
	bridges.Name = "Bridges"
	bridges.Parent = world
	feedback = Instance.new("RemoteEvent")
	feedback.Name = "HeroCavesIslandFeedback"
	feedback.Parent = ReplicatedStorage
	for id = 1, Config.IslandCount do
		local angle = math.rad(Config.StartAngleDegrees + (id - 1) * (Config.AngularSpacingDegrees or 360 / Config.IslandCount))
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local origin = CFrame.lookAt(surface + direction * Config.IslandRadius, surface)
		local model = Instance.new("Model")
		model.Name = "Island" .. id
		model:SetAttribute("IslandId", id)
		model:SetAttribute("OwnerUserId", 0)
		model.Parent = folder
		part("Part", "Platform", Config.IslandSize, origin * CFrame.new(0, -Config.IslandSize.Y / 2, 0), model)
		local markers = Instance.new("Folder")
		markers.Name = "Markers"
		markers.Parent = model
		local zone = part("Part", "ClaimZone", Config.ClaimZoneSize, origin * CFrame.new(Config.ClaimZoneOffset), markers,
			Color3.fromRGB(240, 200, 90))
		zone.CanCollide = false
		zone.CanTouch = true
		zone.Transparency = 0.65
		spawnPoint("PlayerSpawn", origin * CFrame.new(Config.PlayerSpawnOffset), markers)
		marker("CavePosition", origin * CFrame.new(Config.CaveOffset), markers)
		marker("EnemyPosition", origin * CFrame.new(Config.EnemyOffset), markers)
		for name, offset in Config.HeroSlots do marker(name, origin * CFrame.new(offset), markers) end
		local island = {Id = id, Model = model, Markers = markers, Label = sign(zone, "UNCLAIMED"), Owner = nil}
		islands[id] = island
		table.insert(connections, zone.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player and player.Character == character then IslandService.TryClaim(player, id) end
		end))
		-- Bridges connect the hub to the inward edge of each island for manual walking.
		local bridgeStart = math.min(Config.HubSize.X, Config.HubSize.Z) / 2 - 6
		local bridgeEnd = Config.IslandRadius - Config.IslandSize.Z / 2 + 6
		local midpoint = surface + direction * ((bridgeStart + bridgeEnd) / 2)
		midpoint -= Vector3.new(0, Config.BridgeThickness / 2, 0)
		part("Part", "Bridge" .. id, Vector3.new(Config.BridgeWidth, Config.BridgeThickness, bridgeEnd - bridgeStart),
			CFrame.lookAt(midpoint, midpoint + direction), bridges, Color3.fromRGB(110, 100, 85))
	end
	started = true
	table.insert(connections, Players.PlayerAdded:Connect(registerPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(release))
	for _, player in Players:GetPlayers() do registerPlayer(player) end
end

function IslandService.Stop()
	if not started then return end
	started = false
	generation += 1
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	for player in playerConnections do release(player) end
	table.clear(playerIslands)
	table.clear(islands)
	table.clear(lastFeedback)
	if feedback then feedback:Destroy(); feedback = nil end
	if world then world:Destroy(); world = nil end
	hubSpawn = nil
end

return IslandService
