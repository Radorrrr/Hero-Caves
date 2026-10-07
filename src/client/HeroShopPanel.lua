local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local NumberFormatter = require(Shared:WaitForChild("NumberFormatter"))
local HeroShopPanel = {}

function HeroShopPanel.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	if playerGui:FindFirstChild("IdleHeroSimulatorHeroShop") then return end
	local offer = player:WaitForChild("HeroShop")
	local remotes = ReplicatedStorage:WaitForChild("IdleHeroSimulatorRemotes")
	local open = remotes:WaitForChild("OpenHeroShop")
	local purchase = remotes:WaitForChild("PurchaseNextHero")
	local gui = Instance.new("ScreenGui")
	gui.Name = "IdleHeroSimulatorHeroShop"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.Enabled = false
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.8, 0, 0, 380)
	panel.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(430, 380)
	size.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel
	local function item(class, name, y, height, fontSize)
		local obj = Instance.new(class)
		obj.Name = name
		obj.Position = UDim2.fromOffset(20, y)
		obj.Size = UDim2.new(1, -40, 0, height)
		obj.Font = Enum.Font.GothamBold
		obj.TextColor3 = Color3.fromRGB(235, 240, 250)
		obj.TextSize = fontSize
		obj.TextWrapped = true
		obj.BorderSizePixel = 0
		if class == "TextLabel" then obj.BackgroundTransparency = 1 end
		obj.Parent = panel
		return obj
	end
	item("TextLabel", "Title", 12, 32, 22).Text = "HERO SHOP"
	local gold = item("TextLabel", "Gold", 48, 24, 16)
	gold.TextColor3 = Color3.fromRGB(240, 205, 90)
	local name = item("TextLabel", "Hero", 84, 32, 24)
	local stats = item("TextLabel", "Summary", 124, 78, 17)
	local cost = item("TextLabel", "Cost", 206, 28, 18)
	local buy = item("TextButton", "Buy", 244, 40, 17)
	local feedback = item("TextLabel", "Result", 288, 28, 14)
	local close = item("TextButton", "Close", 326, 34, 16)
	close.Text = "CLOSE"
	close.BackgroundColor3 = Color3.fromRGB(65, 75, 90)
	local pending, lastRequest = false, -math.huge
	local function render()
		local balance = player:GetAttribute("Gold") or 0
		local id = offer:GetAttribute("HeroId")
		local price = offer:GetAttribute("Cost") or 0
		local hasOffer = id ~= nil and offer:GetAttribute("OfferToken") ~= nil
		gold.Text = "GOLD: " .. NumberFormatter.Format(balance)
		name.Text = hasOffer and string.upper(offer:GetAttribute("HeroName") or "") or "ALL HEROES UNLOCKED"
		stats.Text = hasOffer and string.format("%s\nDamage: %s\nAttack Speed: %.2f attacks/s",
			offer:GetAttribute("Role") or "", NumberFormatter.Format(offer:GetAttribute("Damage")),
			offer:GetAttribute("AttackSpeed") or 0) or "More heroes coming later."
		cost.Text = hasOffer and ("Cost: " .. NumberFormatter.Format(price) .. " Gold") or ""
		buy.Visible = hasOffer
		local affordable = hasOffer and balance >= price and not pending
		buy.Active, buy.AutoButtonColor = affordable, affordable
		buy.BackgroundColor3 = affordable and Color3.fromRGB(50, 130, 85) or Color3.fromRGB(75, 80, 90)
		buy.Text = pending and "PURCHASING..." or (balance < price and "NOT ENOUGH GOLD"
			or ("BUY " .. string.upper(offer:GetAttribute("HeroName") or "")))
	end
	open.OnClientEvent:Connect(function()
		feedback.Text = ""
		render()
		gui.Enabled = true
	end)
	close.Activated:Connect(function() gui.Enabled = false end)
	buy.Activated:Connect(function()
		local token, price = offer:GetAttribute("OfferToken"), offer:GetAttribute("Cost")
		if not gui.Enabled or pending or not offer:GetAttribute("HeroId") or not token or not price
			or (player:GetAttribute("Gold") or 0) < price then return end
		if time() - lastRequest < GameConfig.Economy.PurchaseCooldown then return end
		lastRequest, pending = time(), true
		feedback.Text = ""
		render()
		-- No hero ID, price, player or ownership sent. The server resolves this offer token.
		purchase:FireServer(token)
	end)
	local messages = {HeroPurchased = "Hero unlocked!", NotEnoughGold = "Not enough gold.",
		AllHeroesOwned = "All heroes unlocked.", OutOfRange = "Return to the Hero Merchant to buy.",
		StaleOffer = "Offer changed. Please try again.", TooFast = "Please wait a moment.",
		InvalidPlayer = "Progression is not available.", InvalidRequest = "Invalid shop request."}
	purchase.OnClientEvent:Connect(function(success, reason)
		pending = false
		feedback.Text = messages[reason] or "Purchase failed."
		feedback.TextColor3 = success and Color3.fromRGB(120, 230, 155) or Color3.fromRGB(245, 145, 135)
		render()
	end)
	-- Attribute replication need not arrive in assignment order; every offer field can refresh the view.
	offer.AttributeChanged:Connect(render)
	player:GetAttributeChangedSignal("Gold"):Connect(render)
	player.CharacterAdded:Connect(function() gui.Enabled = false end)
	render()
	gui.Parent = playerGui
end
return HeroShopPanel
