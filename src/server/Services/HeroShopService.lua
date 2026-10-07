local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Progression = require(script.Parent.ProgressionService)
local Islands = require(script.Parent.IslandService)
local Contexts = require(script.Parent.CombatContexts)
local Heroes = require(script.Parent.HeroService)
local HeroShopService = {}
local records, lastRequest = {}, {}
local started, serial = false, 0
local prompt, promptConnection, openRemote

local function publish(player)
	local record = records[player]
	if not record then return end
	local id = Progression.GetNextHero(player)
	if record.Initialized and record.NextHeroId == id then return end
	record.Initialized, record.NextHeroId = true, id
	serial += 1
	record.Token = tostring(player.UserId) .. ":" .. serial
	local definition = id and HeroConfig[id]
	local folder = record.Folder
	-- Only the current offer is published. No future hero preview/locked entries.
	folder:SetAttribute("HeroId", id)
	folder:SetAttribute("HeroName", definition and definition.Name or nil)
	folder:SetAttribute("Cost", definition and definition.UnlockCost or nil)
	folder:SetAttribute("Damage", definition and definition.BaseDamage or nil)
	folder:SetAttribute("AttackSpeed", definition and 1 / definition.AttackInterval or nil)
	folder:SetAttribute("Role", definition and (definition.CombatStyle == "Bow" and "Fast ranged hero"
		or definition.CombatStyle == "Magic" and "Slow, powerful magic hero" or "Melee hero") or nil)
	folder:SetAttribute("AllOwned", id == nil)
	folder:SetAttribute("OfferToken", record.Token) -- Published last; replay protection is private.
end

local function initialize(player)
	if records[player] then return end
	local folder = Instance.new("Folder")
	folder.Name = "HeroShop"
	records[player] = {Folder = folder}
	publish(player)
	folder.Parent = player
end

local function nearMerchant(player)
	if not player or player.Parent ~= Players or not prompt or not prompt.Enabled or not prompt.Parent then return false end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root ~= nil and root:IsA("BasePart") and humanoid ~= nil and humanoid.Health > 0
		and (root.Position - prompt.Parent.Position).Magnitude <= WorldConfig.HeroShopActivationDistance
end

function HeroShopService.PurchaseNextHero(player, token)
	local record = records[player]
	if not record or player.Parent ~= Players then return false, "InvalidPlayer" end
	local now = time()
	if lastRequest[player] and now - lastRequest[player] < GameConfig.Economy.PurchaseCooldown then return false, "TooFast" end
	lastRequest[player] = now
	if type(token) ~= "string" or token ~= record.Token then return false, "StaleOffer" end
	if not nearMerchant(player) then return false, "OutOfRange" end
	local island = Islands.GetIsland(player)
	if not island or island.Owner ~= player then return false, "ClaimIslandFirst" end
	if Progression.GetNextHero(player) ~= record.NextHeroId then publish(player); return false, "StaleOffer" end
	local success, reason = Progression.PurchaseNextHero(player)
	if success then
		-- Add rigs to the existing owner context without restarting its wave/enemy/loops.
		Heroes.RefreshOwnedHeroes(Contexts.Get(player))
		publish(player)
	end
	return success, reason
end

local function connectPrompt(nextPrompt)
	if promptConnection then promptConnection:Disconnect(); promptConnection = nil end
	prompt = nextPrompt
	if not prompt then return end
	promptConnection = prompt.Triggered:Connect(function(player)
		if not nearMerchant(player) or not records[player] then return end
		publish(player)
		openRemote:FireClient(player)
	end)
end

function HeroShopService.Start()
	if started then return end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("IdleHeroSimulatorRemotes")
	openRemote = Instance.new("RemoteEvent")
	openRemote.Name = "OpenHeroShop"
	openRemote.Parent = remotes
	local purchase = Instance.new("RemoteEvent")
	purchase.Name = "PurchaseNextHero"
	purchase.Parent = remotes
	purchase.OnServerEvent:Connect(function(player, ...)
		if select("#", ...) ~= 1 then purchase:FireClient(player, false, "InvalidRequest"); return end
		local success, reason = HeroShopService.PurchaseNextHero(player, ...)
		purchase:FireClient(player, success, reason)
	end)
	Players.PlayerAdded:Connect(initialize)
	Players.PlayerRemoving:Connect(function(player)
		local record = records[player]
		if record then record.Folder:Destroy(); records[player] = nil end
		lastRequest[player] = nil
	end)
	Progression.HeroOwned:Connect(function(player) publish(player) end)
	Islands.HeroShopChanged:Connect(connectPrompt)
	connectPrompt(Islands.GetHeroShopPrompt())
	for _, player in Players:GetPlayers() do initialize(player) end
end
return HeroShopService
