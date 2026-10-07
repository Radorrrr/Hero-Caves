local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local Contexts = require(script.Parent.CombatContexts)
local Progression = require(script.Parent.ProgressionService)

local HeroUpgradeService = {}
local selections, records = {}, {}
local started, serial = false, 0
local openRemote, closedRemote

local function validHero(player, hero)
	if not player or player.Parent ~= Players or not hero then return false end
	local context = Contexts.Get(player)
	return context ~= nil and hero.Context == context and hero.Owner == player
		and context.HeroesById[hero.Id] == hero and HeroConfig[hero.Id] ~= nil
		and Progression.OwnsHero(player, hero.Id) and hero.Model.Parent ~= nil
		and hero.Model:IsDescendantOf(context.HeroFolder) and hero.Model.PrimaryPart ~= nil
		and hero.Model.PrimaryPart:IsDescendantOf(hero.Model)
		and hero.UpgradePrompt ~= nil and hero.UpgradePrompt.Enabled
		and hero.UpgradePrompt.Parent == hero.Model.PrimaryPart
end

local function clearSelection(player)
	local selection = selections[player]
	selections[player] = nil
	local record = records[player]
	if record then
		record.Folder:SetAttribute("Token", nil)
		record.Folder:SetAttribute("HeroId", nil)
		record.Folder:SetAttribute("ContextId", nil)
	end
	if selection and player.Parent == Players then closedRemote:FireClient(player, selection.Token) end
end

local function initialize(player)
	if records[player] then return end
	local folder = Instance.new("Folder")
	folder.Name = "HeroUpgradeSelection"
	folder.Parent = player
	records[player] = {Folder = folder, CharacterConnection = player.CharacterAdded:Connect(function()
		clearSelection(player)
	end)}
end

function HeroUpgradeService.IsSelectionValid(player, heroId, token)
	local selection = selections[player]
	if not selection or type(token) ~= "string" or token ~= selection.Token
		or heroId ~= selection.Hero.Id then return false end
	if not validHero(player, selection.Hero) then clearSelection(player); return false end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root ~= nil and root:IsA("BasePart") and humanoid ~= nil and humanoid.Health > 0
end

function HeroUpgradeService.Open(player, hero)
	if not started or not records[player] or not validHero(player, hero) then return false end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0
		or (root.Position - hero.Model.PrimaryPart.Position).Magnitude > WorldConfig.HeroUpgradeActivationDistance then
		return false
	end
	serial += 1
	local token = tostring(player.UserId) .. ":" .. serial
	selections[player] = {Hero = hero, Token = token}
	local folder = records[player].Folder
	folder:SetAttribute("HeroId", hero.Id)
	folder:SetAttribute("ContextId", hero.Context.Id)
	folder:SetAttribute("Token", token)
	openRemote:FireClient(player, hero.Model, hero.Id, token)
	return true
end

function HeroUpgradeService.Detach(hero)
	if selections[hero.Owner] and selections[hero.Owner].Hero == hero then clearSelection(hero.Owner) end
	if hero.UpgradeConnection then hero.UpgradeConnection:Disconnect(); hero.UpgradeConnection = nil end
	if hero.UpgradeAncestryConnection then hero.UpgradeAncestryConnection:Disconnect(); hero.UpgradeAncestryConnection = nil end
	if hero.UpgradePrompt then hero.UpgradePrompt:Destroy(); hero.UpgradePrompt = nil end
end

function HeroUpgradeService.Attach(hero)
	if hero.UpgradePrompt then return end
	assert(started, "HeroUpgradeService must start before spawning heroes")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UpgradeHero"
	prompt.ActionText = "Upgrade"
	prompt.ObjectText = hero.Config.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = WorldConfig.HeroUpgradeActivationDistance
	prompt.Enabled = true
	prompt.Parent = hero.Model.PrimaryPart
	hero.UpgradePrompt = prompt
	hero.UpgradeConnection = prompt.Triggered:Connect(function(player)
		HeroUpgradeService.Open(player, hero)
	end)
	hero.UpgradeAncestryConnection = hero.Model.AncestryChanged:Connect(function()
		local folder = hero.Context.HeroFolder
		if not folder or not hero.Model:IsDescendantOf(folder) then HeroUpgradeService.Detach(hero) end
	end)
end

function HeroUpgradeService.Start()
	if started then return end
	assert(WorldConfig.HeroUpgradeActivationDistance > 0, "Invalid hero activation distance")
	started = true
	local remotes = ReplicatedStorage:WaitForChild("IdleHeroSimulatorRemotes")
	local function remote(name)
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = remotes
		return event
	end
	openRemote = remote("OpenHeroUpgrade")
	closedRemote = remote("HeroUpgradeClosed")
	remote("CloseHeroUpgrade").OnServerEvent:Connect(function(player, ...)
		if select("#", ...) ~= 1 then return end
		local token = ...
		if selections[player] and selections[player].Token == token then clearSelection(player) end
	end)
	Progression.SetHeroInteractionValidator(HeroUpgradeService.IsSelectionValid)
	Contexts.Changed:Connect(function(player)
		local selection = selections[player]
		if selection and not validHero(player, selection.Hero) then clearSelection(player) end
	end)
	Players.PlayerAdded:Connect(initialize)
	Players.PlayerRemoving:Connect(function(player)
		clearSelection(player)
		local record = records[player]
		if record then record.CharacterConnection:Disconnect(); record.Folder:Destroy(); records[player] = nil end
	end)
	for _, player in Players:GetPlayers() do initialize(player) end
end

return HeroUpgradeService
