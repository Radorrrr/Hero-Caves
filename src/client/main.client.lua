local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local NumberFormatter = require(Shared:WaitForChild("NumberFormatter"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local HeroConfig = require(Shared:WaitForChild("HeroConfig"))
local heroId = HeroConfig.StartingHeroId
local definition = HeroConfig[heroId]
local heroData = player:WaitForChild("HeroProgression"):WaitForChild(heroId)
local upgradeStates = heroData:WaitForChild("Upgrades")
local remotes = ReplicatedStorage:WaitForChild("HeroCavesRemotes")
local buyLevel = remotes:WaitForChild("BuyHeroLevel")
local buyUpgrade = remotes:WaitForChild("BuyUpgrade")

if playerGui:FindFirstChild("HeroCavesProgression") then
	return
end
local gui = Instance.new("ScreenGui")
gui.Name = "HeroCavesProgression"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 16, 1, -16)
panel.Size = UDim2.new(0, 330, 0.88, 0)
panel.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
panel.BorderSizePixel = 0
panel.Parent = gui
local constraint = Instance.new("UISizeConstraint")
constraint.MinSize = Vector2.new(280, 400)
constraint.MaxSize = Vector2.new(330, 650)
constraint.Parent = panel
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local function label(name, y, height, fontSize, parent)
	local text = Instance.new("TextLabel")
	text.Name = name
	text.Position = UDim2.fromOffset(16, y)
	text.Size = UDim2.new(1, -32, 0, height)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.fromRGB(235, 240, 250)
	text.Font = Enum.Font.Gotham
	text.TextSize = fontSize
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextWrapped = true
	text.Parent = parent or panel
	return text
end

local function button(name, y, parent)
	local result = Instance.new("TextButton")
	result.Name = name
	result.Position = UDim2.fromOffset(16, y)
	result.Size = UDim2.new(1, -32, 0, 36)
	result.Font = Enum.Font.GothamBold
	result.TextSize = 16
	result.TextColor3 = Color3.fromRGB(255, 255, 255)
	result.BorderSizePixel = 0
	result.Parent = parent or panel
	return result
end

local function styleButton(target, enabled)
	target.Active = enabled
	target.AutoButtonColor = enabled
	target.BackgroundColor3 = enabled and Color3.fromRGB(50, 130, 85) or Color3.fromRGB(75, 80, 90)
end

local goldLabel = label("Gold", 12, 36, 24)
goldLabel.TextColor3 = Color3.fromRGB(240, 205, 90)
local title = label("Hero", 53, 25, 19)
title.Text = string.upper(definition.Name) .. " · Your progression"
local levelLabel = label("Level", 83, 24, 18)
local damageLabel = label("Damage", 110, 24, 18)
local bonusLabel = label("GoldBonus", 138, 22, 14)
local levelButton = button("LevelUp", 168)
local feedback = label("PurchaseResult", 207, 24, 14)
feedback.Text = ""
local ownerLabel = label("CombatOwner", 234, 48, 13)
ownerLabel.TextColor3 = Color3.fromRGB(180, 190, 210)
local milestonesTitle = label("MilestonesTitle", 288, 24, 17)
milestonesTitle.Text = "Milestone upgrades"
local list = Instance.new("ScrollingFrame")
list.Name = "Milestones"
list.Position = UDim2.fromOffset(8, 320)
list.Size = UDim2.new(1, -16, 1, -332)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.CanvasSize = UDim2.fromOffset(0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local lastRequestAt = -math.huge
local function request(event, ...)
	if time() - lastRequestAt < GameConfig.Economy.PurchaseCooldown then
		return
	end
	lastRequestAt = time()
	-- Only stable IDs are sent. All cost/effect decisions remain on the server.
	event:FireServer(...)
end

local rows = {}
for index, upgrade in definition.Milestones or {} do
	local row = Instance.new("Frame")
	row.Name = upgrade.Id
	row.Size = UDim2.new(1, -10, 0, 162)
	row.LayoutOrder = index
	row.BackgroundColor3 = Color3.fromRGB(37, 43, 55)
	row.BorderSizePixel = 0
	row.Parent = list
	label("Name", 6, 24, 16, row).Text = upgrade.Name
	label("RequiredLevel", 33, 20, 14, row).Text = "Requires Level " .. tostring(upgrade.Level)
	label("Description", 56, 38, 14, row).Text = upgrade.Description
	label("Cost", 96, 20, 14, row).Text = NumberFormatter.Format(upgrade.Cost) .. " Gold"
	local buyButton = button("Buy", 120, row)
	rows[upgrade.Id] = {Button = buyButton, Definition = upgrade}
	buyButton.Activated:Connect(function()
		local gold = player:GetAttribute("Gold")
		if upgradeStates:GetAttribute(upgrade.Id) == "Available" and gold and gold >= upgrade.Cost then
			request(buyUpgrade, heroId, upgrade.Id)
		end
	end)
end

local function render()
	local gold = player:GetAttribute("Gold")
	local level = heroData:GetAttribute("Level")
	local damage = heroData:GetAttribute("Damage")
	local cost = heroData:GetAttribute("NextLevelCost")
	local maxLevel = heroData:GetAttribute("AtMaxLevel")
	local ready = gold ~= nil and level ~= nil and damage ~= nil and cost ~= nil
	local affordable = ready and not maxLevel and gold >= cost
	goldLabel.Text = "GOLD: " .. NumberFormatter.Format(gold)
	levelLabel.Text = "Level " .. NumberFormatter.Format(level)
	damageLabel.Text = "Damage: " .. NumberFormatter.Format(damage)
	bonusLabel.Text = "Gold earned x" .. tostring(player:GetAttribute("GoldMultiplier") or 1)
	levelButton.Text = not ready and "Loading..." or (maxLevel and "Maximum level"
		or ("Level Up — " .. NumberFormatter.Format(cost) .. " Gold"))
	styleButton(levelButton, affordable)
	if player:GetAttribute("IsHeroCombatOwner") then
		ownerLabel.Text = "The shared hero uses your levels and upgrades."
	else
		ownerLabel.Text = "Shared hero uses another player's stats. Your purchases and gold bonuses remain personal."
	end
	for upgradeId, row in rows do
		local state = upgradeStates:GetAttribute(upgradeId)
		local canBuy = state == "Available" and gold ~= nil and gold >= row.Definition.Cost
		styleButton(row.Button, canBuy)
		if state == "Purchased" then
			row.Button.Text = "PURCHASED"
		elseif state == "Locked" then
			row.Button.Text = "LOCKED"
		elseif state == "Available" then
			row.Button.Text = canBuy and ("BUY — " .. NumberFormatter.Format(row.Definition.Cost) .. " GOLD")
				or "AVAILABLE — Need gold"
		else
			row.Button.Text = "Loading..."
		end
	end
end

for _, name in {"Gold", "GoldMultiplier", "IsHeroCombatOwner"} do
	player:GetAttributeChangedSignal(name):Connect(render)
end
heroData.AttributeChanged:Connect(render)
upgradeStates.AttributeChanged:Connect(render)
levelButton.Activated:Connect(function()
	local gold = player:GetAttribute("Gold")
	local cost = heroData:GetAttribute("NextLevelCost")
	if gold ~= nil and cost ~= nil and gold >= cost and not heroData:GetAttribute("AtMaxLevel") then
		request(buyLevel, heroId)
	end
end)
local messages = {
	LevelPurchased = "Hero leveled up!",
	UpgradePurchased = "Upgrade purchased!",
	NotEnoughGold = "Not enough gold.",
	MaxLevel = "Maximum prototype level reached.",
	InvalidPlayer = "Progression is not available.",
	InvalidHero = "Unknown hero.",
	InvalidUpgrade = "Unknown upgrade.",
	Locked = "Required level not reached.",
	AlreadyPurchased = "Already purchased.",
}
local function purchaseResult(success, reason)
	feedback.Text = messages[reason] or "Purchase failed."
	feedback.TextColor3 = success and Color3.fromRGB(120, 230, 155) or Color3.fromRGB(245, 145, 135)
	render()
end
buyLevel.OnClientEvent:Connect(purchaseResult)
buyUpgrade.OnClientEvent:Connect(purchaseResult)
render()
gui.Parent = playerGui
