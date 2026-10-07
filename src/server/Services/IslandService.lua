local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.WorldConfig)

local Data = require(script.Parent.PlayerDataService)
local IslandService = {}
local claimedEvent = Instance.new("BindableEvent")
local releasingEvent = Instance.new("BindableEvent")
IslandService.Claimed = claimedEvent.Event
IslandService.Releasing = releasingEvent.Event
local islands = {}
local playerIslands = {}
local playerConnections = {}
local connections = {}
local lastFeedback = {}
local world, hubSpawn, feedback
local started = false
local generation = 0
local shopPrompt
local shopChanged = Instance.new("BindableEvent")
IslandService.HeroShopChanged = shopChanged.Event

function IslandService.GetHeroShopPrompt()
	return shopPrompt
end

local function part(class, name, size, frame, parent, color)
	local object = Instance.new(class)
	object.Name = name
	object.Size = size
	object.CFrame = frame
	object.Anchored = true
	object.CanCollide = true
	object.Transparency = 0
	object.Reflectance = 0
	object.CastShadow = true
	object.Color = color or Color3.fromRGB(80, 105, 100)
	object.Material = Enum.Material.SmoothPlastic
	object.Parent = parent
	return object
end

local function hideReference(object)
	object.Transparency = 1
	object.CastShadow = false
	object.CanCollide = false
	object.CanTouch = false
	object.CanQuery = false
	-- Part transparency alone does not hide independently rendered textures.
	for _, child in object:GetDescendants() do
		if child:IsA("Decal") or child:IsA("Texture") then child.Transparency = 1 end
	end
	if object:IsA("SpawnLocation") then
		-- Spawn decals added after parenting must remain invisible too.
		table.insert(connections, object.DescendantAdded:Connect(function(child)
			if child:IsA("Decal") or child:IsA("Texture") then child.Transparency = 1 end
		end))
	end
end

-- Hide legacy Studio spawn plates in the Hub footprint without deleting spawn objects.
local function hideLegacyHubSpawns()
	local surfaceY = Config.HubPosition.Y + Config.HubSize.Y / 2
	local hidden = 0
	for _, object in workspace:GetDescendants() do
		if object:IsA("SpawnLocation") and (not world or not object:IsDescendantOf(world)) then
			local position = object.Position
			if math.abs(position.X - Config.HubPosition.X) <= Config.HubSize.X / 2
				and math.abs(position.Z - Config.HubPosition.Z) <= Config.HubSize.Z / 2
				and math.abs(position.Y - surfaceY) <= 8 then
				hideReference(object)
				hidden += 1
			end
		end
	end
	return hidden
end

local function marker(name, frame, parent)
	local object = part("Part", name, Vector3.new(1, 1, 1), frame, parent)
	hideReference(object)
	return object
end

local function spawnPoint(name, frame, parent)
	local spawn = part("SpawnLocation", name, Vector3.new(8, 1, 8), frame, parent)
	hideReference(spawn)
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Enabled = true
	return spawn
end

-- Runtime removal includes pre-existing Parts inside Models, not only Workspace.Baseplate.
function IslandService.RemoveGlobalFloors()
	local surfaceY = Config.HubPosition.Y + Config.HubSize.Y / 2
	local footprint = Config.IslandRadius + math.max(Config.IslandSize.X, Config.IslandSize.Z) / 2
	local removed = 0
	for _, object in workspace:GetDescendants() do
		if not object:IsA("BasePart") or not object.Anchored then continue end
		if world and object:IsDescendantOf(world) then continue end
		local size, position = object.Size, object.Position
		local name = string.lower(object.Name)
		local namedFloor = Config.GlobalFloorNames[name] and (name == "baseplate"
			or (size.X >= Config.HubSize.X and size.Z >= Config.HubSize.Z))
		local broadFloor = size.X >= Config.GlobalFloorMinimumSize.X and size.Z >= Config.GlobalFloorMinimumSize.Z
		if not namedFloor and not broadFloor then continue end
		local horizontal = math.abs(object.CFrame.UpVector.Y) > 0.99 and size.Y <= math.min(size.X, size.Z) / 4
		local underneath = position.Y + size.Y / 2 <= surfaceY + Config.GlobalFloorTopTolerance
		local inWorld = math.abs(position.X - Config.HubPosition.X) <= footprint + size.X / 2
			and math.abs(position.Z - Config.HubPosition.Z) <= footprint + size.Z / 2
		if (namedFloor or broadFloor) and horizontal and underneath and inWorld then
			print("[IslandService] Removing global floor: " .. object:GetFullName())
			object:Destroy()
			removed += 1
		end
	end
	return removed
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

local function clearOwnerAvatar(island)
	if island.OwnerAvatar then island.OwnerAvatar:Destroy(); island.OwnerAvatar = nil end
	island.Label.Parent.Enabled = true
end

local function showOwnerAvatar(island, player)
	clearOwnerAvatar(island)
	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerAvatar"
	gui.Adornee = island.Markers.ClaimZone
	gui.Size = UDim2.fromOffset(300, 140)
	gui.StudsOffsetWorldSpace = Vector3.new(0, Config.OwnerAvatarHeight, 0)
	gui.MaxDistance = Config.OwnerAvatarMaxDistance
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui:SetAttribute("OwnerUserId", player.UserId)
	local image = Instance.new("ImageLabel")
	image.Name = "Headshot"
	image.Size = UDim2.fromOffset(88, 88)
	image.Position = UDim2.new(0.5, -44, 0, 0)
	image.BackgroundColor3 = Color3.fromRGB(40, 50, 65)
	image.BorderSizePixel = 0
	image.Image = ""
	image.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = image
	local fallback = Instance.new("TextLabel")
	fallback.Name = "Fallback"
	fallback.Size = UDim2.fromScale(1, 1)
	fallback.BackgroundTransparency = 1
	fallback.Text = "PLAYER"
	fallback.Visible = true
	fallback.TextColor3 = Color3.fromRGB(235, 240, 250)
	fallback.Font = Enum.Font.GothamBold
	fallback.TextSize = 14
	fallback.Parent = image
	local ownerName = Instance.new("TextLabel")
	ownerName.Name = "OwnerName"
	ownerName.Position = UDim2.fromOffset(0, 94)
	ownerName.Size = UDim2.new(1, 0, 0, 44)
	ownerName.BackgroundTransparency = 1
	ownerName.Text = island.Label.Text
	ownerName.TextColor3 = Color3.fromRGB(255, 255, 255)
	ownerName.TextStrokeTransparency = 0.3
	ownerName.Font = Enum.Font.GothamBold
	ownerName.TextSize = 22
	ownerName.TextWrapped = true
	ownerName.Parent = gui
	-- Stack portrait/name in one billboard so they cannot overlap at long distances.
	island.Label.Parent.Enabled = false
	gui.Parent = island.Model
	island.OwnerAvatar = gui
	-- Fetch can yield/fail. It must never delay ownership or change a reused island's icon.
	task.spawn(function()
		local success, content, ready = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size180x180)
		end)
		if island.Owner ~= player or island.OwnerAvatar ~= gui or not gui.Parent then return end
		if success and ready and type(content) == "string" and content ~= "" then
			image.Image = content
			fallback.Visible = false
		end
	end)
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
	-- Walls end at roof underside Y=10; side walls end at back wall front Z=4.
	part("Part", "Left", Vector3.new(4, 10, 10), origin * CFrame.new(-7, 5, -1), model, color)
	part("Part", "Right", Vector3.new(4, 10, 10), origin * CFrame.new(7, 5, -1), model, color)
	part("Part", "Roof", Vector3.new(18, 4, 12), origin * CFrame.new(0, 12, 0), model, color)
	part("Part", "Back", Vector3.new(18, 10, 2), origin * CFrame.new(0, 5, 5), model, color)
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

local function rootInsideZone(root, island)
	local zone = island.Markers.ClaimZone
	local point = zone.CFrame:PointToObjectSpace(root.Position)
	local half = zone.Size / 2
	return math.abs(point.X) <= half.X and math.abs(point.Y) <= half.Y
		and math.abs(point.Z) <= half.Z
end

local function insideZone(player, island)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return false end
	return rootInsideZone(root, island)
end

-- Server-only entry point; no ownership-request remote exists.
function IslandService.TryClaim(player, islandId)
	local island = islands[islandId]
	if not started or not island or not player or not Data.IsReady(player) or not insideZone(player, island) then
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
	showOwnerAvatar(island, player)
	-- BindableEvents copy Lua tables. Send the stable runtime Model, not our ownership record.
	if RunService:IsStudio() then
		print(string.format("[CombatContext] Claim confirmed: %s -> %s; notifying combat", player.Name, island.Model.Name))
	end
	claimedEvent:Fire(player, island.Model)
	showFeedback(player, "Island " .. island.Id .. " claimed. This is your cave.")
	return true, "Claimed"
end

local function detectClaim(player, islandId, source)
	-- Both detection paths use the same non-yielding ownership validation/assignment.
	local success = IslandService.TryClaim(player, islandId)
	if success and RunService:IsStudio() then
		print(string.format("[IslandService] Claim successful via %s: %s -> Island%d", source, player.Name, islandId))
	end
	return success
end

function IslandService.ReleaseIsland(player)
	local island = playerIslands[player]
	if island then
		releasingEvent:Fire(player, island.Model)
		clearOwnerAvatar(island)
		island.Owner = nil
		playerIslands[player] = nil
		island.Model:SetAttribute("OwnerUserId", 0)
		island.Label.Text = "UNCLAIMED"
		island.Markers.ClaimZone.Color = Color3.fromRGB(240, 200, 90)
		if island.Cave then island.Cave:Destroy(); island.Cave = nil end
	end
	player:SetAttribute("IslandId", nil)
	player.RespawnLocation = player.Parent == Players and hubSpawn or nil
	return island ~= nil
end

local function release(player)
	IslandService.ReleaseIsland(player)
	lastFeedback[player] = nil
	if playerConnections[player] then playerConnections[player]:Disconnect(); playerConnections[player] = nil end
	player.RespawnLocation = nil
end

local function returnToSpawn(player, character, root)
	local spawn = IslandService.GetSpawnLocation(player)
	if not spawn then return end
	character:PivotTo(spawn.CFrame * CFrame.new(0, 3, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
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
		returnToSpawn(player, character, root)
	end
	playerConnections[player] = player.CharacterAdded:Connect(positionCharacter)
	if player.Character then task.spawn(positionCharacter, player.Character) end
end

local function createHeroShop(hub, surface)
	local model = Instance.new("Model")
	model.Name = "HeroShop"
	local origin = CFrame.new(surface + Config.HeroShopOffset)
	local function body(name, size, offset, color)
		local obj = part("Part", name, size, origin * CFrame.new(offset), model, color)
		obj.CanCollide = false
		return obj
	end
	body("Torso", Vector3.new(2.5, 3, 1.5), Vector3.new(0, 3.5, 0), Color3.fromRGB(55, 100, 135))
	local head = body("Head", Vector3.new(1.8, 1.8, 1.8), Vector3.new(0, 5.9, 0), Color3.fromRGB(225, 180, 135))
	body("Hat", Vector3.new(2.4, 0.5, 2.4), Vector3.new(0, 7.05, 0), Color3.fromRGB(200, 160, 65))
	for _, side in {-1, 1} do
		body(side == -1 and "LeftLeg" or "RightLeg", Vector3.new(1, 2, 1.3), Vector3.new(side * 0.65, 1, 0), Color3.fromRGB(55, 55, 65))
		body(side == -1 and "LeftArm" or "RightArm", Vector3.new(0.8, 2.8, 1), Vector3.new(side * 1.7, 3.6, 0), Color3.fromRGB(225, 180, 135))
	end
	model.PrimaryPart = head
	sign(head, "HERO SHOP")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenHeroShop"
	prompt.ActionText = "Hero Shop"
	prompt.ObjectText = "Hero Merchant"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.HeroShopActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
	prompt.Parent = head
	model.Parent = hub
	return prompt
end

function IslandService.Start()
	if started then return end
	assert(Config.BridgeSurfaceDrop > 0, "Bridge top must be below platform surface")
	assert(Config.IslandCount >= 1 and Config.IslandCount % 1 == 0, "Invalid island count")
	assert(Config.IslandRadius > Config.HubSize.X / 2 + Config.IslandSize.Z / 2, "Islands must be outside Hub")
	assert(not workspace:FindFirstChild(Config.FolderName), "World folder already exists")
	assert(Config.VoidDepth > 0 and Config.VoidCheckInterval > 0, "Invalid void recovery settings")
	assert(Config.ClaimCheckInterval > 0 and Config.ClaimCheckInterval <= 0.25, "Invalid claim check interval")
	local removedFloors = IslandService.RemoveGlobalFloors()
	local hiddenSpawns = hideLegacyHubSpawns()
	generation += 1
	world = Instance.new("Folder")
	world.Name = Config.FolderName
	world.Parent = workspace
	world:SetAttribute("RemovedGlobalFloorCount", removedFloors)
	world:SetAttribute("HiddenLegacyHubSpawns", hiddenSpawns)
	local hub = Instance.new("Model")
	hub.Name = "Hub"
	hub.Parent = world
	local hubFrame = CFrame.new(Config.HubPosition)
	part("Part", "Platform", Config.HubSize, hubFrame, hub, Color3.fromRGB(90, 110, 145))
	local surface = Config.HubPosition + Vector3.new(0, Config.HubSize.Y / 2, 0)
	hubSpawn = spawnPoint("PlayerSpawn", CFrame.new(surface + Config.HubSpawnOffset), hub)
	local titleAnchor = Instance.new("Attachment")
	titleAnchor.Name = "HubTitleAnchor"
	titleAnchor.Position = Vector3.new(0, Config.HubSize.Y / 2 + Config.HubTitleHeight, 0)
	titleAnchor.Parent = hub.Platform
	local title = sign(titleAnchor, "IDLE HERO SIMULATOR · HUB")
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Parent.Name = "HubTitle"
	title.Parent.Size = UDim2.fromOffset(520, 70)
	title.Parent.StudsOffset = Vector3.zero
	title.Parent.StudsOffsetWorldSpace = Vector3.zero
	title.Parent.AlwaysOnTop = false
	title.Parent.MaxDistance = 350
	shopPrompt = createHeroShop(hub, surface)
	shopChanged:Fire(shopPrompt) -- Stable Instance identity across BindableEvent.
	local folder = Instance.new("Folder")
	folder.Name = "Islands"
	folder.Parent = world
	local bridges = Instance.new("Folder")
	bridges.Name = "Bridges"
	bridges.Parent = world
	feedback = Instance.new("RemoteEvent")
	feedback.Name = "IdleHeroSimulatorIslandFeedback"
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
		hideReference(zone)
		zone.CanTouch = true -- Functional touch volume; no technical geometry is rendered.
		spawnPoint("PlayerSpawn", origin * CFrame.new(Config.PlayerSpawnOffset), markers)
		marker("CavePosition", origin * CFrame.new(Config.CaveOffset), markers)
		marker("EnemyPosition", origin * CFrame.new(Config.EnemyOffset), markers)
		for name, offset in Config.HeroSlots do marker(name, origin * CFrame.new(offset), markers) end
		local island = {Id = id, Model = model, Markers = markers, Label = sign(zone, "UNCLAIMED"), Owner = nil}
		islands[id] = island
		table.insert(connections, zone.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player and player.Character == character then detectClaim(player, id, "Touched") end
		end))
		-- Bridges connect the hub to the inward edge of each island for manual walking.
		local bridgeStart = math.min(Config.HubSize.X, Config.HubSize.Z) / 2 - 6
		local bridgeEnd = Config.IslandRadius - Config.IslandSize.Z / 2 + 6
		local midpoint = surface + direction * ((bridgeStart + bridgeEnd) / 2)
		midpoint -= Vector3.new(0, Config.BridgeThickness / 2 + Config.BridgeSurfaceDrop, 0)
		part("Part", "Bridge" .. id, Vector3.new(Config.BridgeWidth, Config.BridgeThickness, bridgeEnd - bridgeStart),
			CFrame.lookAt(midpoint, midpoint + direction), bridges, Color3.fromRGB(110, 100, 85))
	end
	started = true
	table.insert(connections, Players.PlayerAdded:Connect(registerPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(release))
	for _, player in Players:GetPlayers() do registerPlayer(player) end
	local nextClaimCheck, nextVoidCheck = 0, 0
	local voidY = surface.Y - Config.VoidDepth
	table.insert(connections, RunService.Heartbeat:Connect(function()
		local now = time()
		local checkClaims, checkVoid = now >= nextClaimCheck, now >= nextVoidCheck
		if not checkClaims and not checkVoid then return end
		if checkClaims then nextClaimCheck = now + Config.ClaimCheckInterval end
		if checkVoid then nextVoidCheck = now + Config.VoidCheckInterval end
		for player in playerConnections do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if player.Parent == Players and root and humanoid and humanoid.Health > 0 then
				if checkVoid and root.Position.Y < voidY then
					returnToSpawn(player, character, root)
				elseif checkClaims and not playerIslands[player] then
					-- Direct references only: at most six zones per eligible live player, at 10 Hz.
					for id, island in islands do
						if not island.Owner and rootInsideZone(root, island) then
							detectClaim(player, id, "occupancy fallback")
							break
						end
					end
				end
			end
		end
	end))
end

function IslandService.Stop()
	if not started then return end
	started = false
	shopPrompt = nil
	shopChanged:Fire(nil)
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
