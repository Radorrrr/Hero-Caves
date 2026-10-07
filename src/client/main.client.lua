local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local NumberFormatter = require(Shared:WaitForChild("NumberFormatter"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local HeroConfig = require(Shared:WaitForChild("HeroConfig"))
local progression = player:WaitForChild("HeroProgression")
local heroSnapshots = {}
for _, id in HeroConfig.HeroOrder do
	local data = progression:WaitForChild(id)
	heroSnapshots[id] = {Data = data, Upgrades = data:WaitForChild("Upgrades"), Quotes = data:WaitForChild("PurchaseModes")}
end
local heroId = HeroConfig.StartingHeroId
local remotes = ReplicatedStorage:WaitForChild("IdleHeroSimulatorRemotes")
local buyLevel = remotes:WaitForChild("BuyHeroLevels")
local purchaseModes = {"x1", "x10", "x25", "x100", "MAX", "NEXT"}
local modeIndex = 1
local buyUpgrade = remotes:WaitForChild("BuyUpgrade")
local openUpgrade = remotes:WaitForChild("OpenHeroUpgrade")
local closedUpgrade = remotes:WaitForChild("HeroUpgradeClosed")
local closeUpgrade = remotes:WaitForChild("CloseHeroUpgrade")
local selection, ancestryConnection

if playerGui:FindFirstChild("IdleHeroSimulatorProgression") then return end
local gui = Instance.new("ScreenGui")
gui.Name = "IdleHeroSimulatorProgression"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 0)
panel.Position = UDim2.fromOffset(16, 72)
panel.Size = UDim2.new(0, 360, 0.8, -72)
panel.Visible = false
panel.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
panel.BorderSizePixel = 0
panel.Parent = gui
local constraint = Instance.new("UISizeConstraint")
constraint.MinSize = Vector2.new(300, 500)
constraint.MaxSize = Vector2.new(360, 760)
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

local goldLabel = label("Gold", 12, 36, 24, gui)
goldLabel.Size = UDim2.fromOffset(260, 36)
goldLabel.TextColor3 = Color3.fromRGB(240, 205, 90)
local title = label("Hero", 16, 26, 19)
local levelLabel = label("Level", 49, 24, 17)
local damageLabel = label("Damage", 77, 24, 17)
local speedLabel = label("AttackSpeed", 105, 22, 15)
local dpsLabel = label("DPS", 131, 22, 15)
local nextCostLabel = label("NextLevelCost", 157, 56, 14)
local bonusLabel = label("GoldMultiplier", 217, 22, 14)
local totalLabel = label("TotalDPS", 0, 60, 22, gui)
totalLabel.AnchorPoint = Vector2.new(1, 0)
totalLabel.Position = UDim2.new(1, -16, 0, 12)
totalLabel.Size = UDim2.fromOffset(200, 60)
totalLabel.TextXAlignment = Enum.TextXAlignment.Right
local levelButton = button("LevelUp", 246)
local modeButton = button("BuyMode", 246)
modeButton.Size = UDim2.new(0, 125, 0, 36)
modeButton.TextSize = 13
modeButton.BackgroundColor3 = Color3.fromRGB(55, 95, 145)
levelButton.Position = UDim2.fromOffset(147, 246)
levelButton.Size = UDim2.new(1, -163, 0, 36)
levelButton.TextSize = 13
levelButton.TextWrapped = true
local feedback = label("PurchaseResult", 286, 24, 14)
feedback.Text = ""
local milestonesTitle = label("MilestonesTitle", 324, 24, 17)
milestonesTitle.Text = "Milestone upgrades"
local list = Instance.new("ScrollingFrame")
list.Name = "Milestones"
list.Position = UDim2.fromOffset(8, 356)
list.Size = UDim2.new(1, -16, 1, -368)
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

local closeButton = button("Close", 12)
closeButton.Text = "CLOSE"
closeButton.Position = UDim2.new(1, -96, 0, 12)
closeButton.Size = UDim2.fromOffset(80, 30)
closeButton.BackgroundColor3 = Color3.fromRGB(75, 80, 90)
title.Size = UDim2.new(1, -120, 0, 26)
local function closeMenu(notifyServer)
	local old = selection
	selection = nil
	panel.Visible = false
	if ancestryConnection then ancestryConnection:Disconnect(); ancestryConnection = nil end
	if notifyServer and old then closeUpgrade:FireServer(old.Token) end
end
closeButton.Activated:Connect(function() closeMenu(true) end)
local lastRequestAt = -math.huge
local function request(event, ...)
	if not selection or not panel.Visible or time() - lastRequestAt < GameConfig.Economy.PurchaseCooldown then return end
	lastRequestAt = time()
	-- IDs and a selection token only; ownership, prices and effects are server decisions.
	local args = table.pack(...)
	args.n += 1; args[args.n] = selection.Token
	event:FireServer(table.unpack(args, 1, args.n))
end
local rows = {}
local function rebuildMilestones()
	for _, row in rows do row.Frame:Destroy() end
	table.clear(rows)
	list.CanvasPosition = Vector2.new(0, 0)
	local rowHeroId = heroId
	local snapshot = heroSnapshots[rowHeroId]
	for index, upgrade in HeroConfig[rowHeroId].Milestones or {} do
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
		rows[upgrade.Id] = {Frame = row, Button = buyButton, Definition = upgrade}
		buyButton.Activated:Connect(function()
			local gold = player:GetAttribute("Gold")
			if selection and heroId == rowHeroId and snapshot.Data:GetAttribute("Owned") and snapshot.Upgrades:GetAttribute(upgrade.Id) == "Available"
				and gold and gold >= upgrade.Cost then
				request(buyUpgrade, rowHeroId, upgrade.Id)
			end
		end)
	end
end

local function render()
	local gold = player:GetAttribute("Gold")
	goldLabel.Text = "GOLD: " .. NumberFormatter.Format(gold)
	totalLabel.Text = "Total DPS\n" .. NumberFormatter.Format(player:GetAttribute("TotalDPS"))
	if not selection then return end
	if not player:GetAttribute("HasCombatArea") or not heroSnapshots[heroId].Data:GetAttribute("Owned") then
		closeMenu(true); return
	end
	local snapshot = heroSnapshots[heroId]
	local data = snapshot.Data
	local definition = HeroConfig[heroId]
	local owned = data:GetAttribute("Owned") == true
	local level = data:GetAttribute("Level")
	local damage = data:GetAttribute("Damage")
	local cost = data:GetAttribute("NextLevelCost")
	local maxLevel = data:GetAttribute("AtMaxLevel")
	local multiplier = string.format("%.2f", player:GetAttribute("GoldMultiplier") or 1):gsub("0+$", ""):gsub("%.$", "")
	bonusLabel.Text = "Gold Multiplier: x" .. multiplier
	speedLabel.Text = owned and string.format("Attack Speed: %.2f attacks/s", data:GetAttribute("AttackSpeed") or 0) or ""
	dpsLabel.Text = owned and ("DPS: " .. NumberFormatter.Format(data:GetAttribute("DPS"))) or ""
	nextCostLabel.Text = owned and (maxLevel and "Next Level: Maximum level" or ("Next Level: " .. NumberFormatter.Format(cost) .. " Gold")) or ""
	local mode = purchaseModes[modeIndex]
	local quote = snapshot.Quotes:FindFirstChild(mode)
	local count = quote and quote:GetAttribute("Count") or 0
	local bulkCost = quote and quote:GetAttribute("Cost") or 0
	local target = quote and quote:GetAttribute("Target") or 0
	modeButton.Text = "BUY MODE: " .. mode
	local affordable = gold ~= nil and owned and count > 0 and not maxLevel
	title.Text = string.upper(definition.Name) .. " · OWNED"
	levelLabel.Text = "Level " .. NumberFormatter.Format(level)
	damageLabel.Text = "Damage: " .. NumberFormatter.Format(damage)
	if owned and not maxLevel then
		nextCostLabel.Text ..= "\n" .. (mode == "NEXT" and (target > 0 and ("Next Milestone: Level " .. tostring(target)) or "NEXT: x1 after final milestone")
			or ("Buy " .. mode)) .. " · +" .. tostring(count) .. " Levels · " .. NumberFormatter.Format(bulkCost) .. " Gold"
	end
	levelButton.Text = maxLevel and "Maximum level" or ("Level Up +" .. tostring(count) .. "\n" .. NumberFormatter.Format(bulkCost) .. " Gold")
	styleButton(levelButton, affordable)
	for upgradeId, row in rows do
		local state = snapshot.Upgrades:GetAttribute(upgradeId)
		local canBuy = owned and state == "Available" and gold ~= nil and gold >= row.Definition.Cost
		styleButton(row.Button, canBuy)
		if state == "Purchased" then row.Button.Text = "PURCHASED"
		elseif state == "Locked" then row.Button.Text = "LOCKED"
		elseif state == "Available" then
			row.Button.Text = canBuy and ("BUY — " .. NumberFormatter.Format(row.Definition.Cost) .. " GOLD") or "AVAILABLE — Need gold"
		else row.Button.Text = "Loading..." end
	end
end
openUpgrade.OnClientEvent:Connect(function(model, id, token)
	if not heroSnapshots[id] or type(token) ~= "string" or not model or not model:IsA("Model")
		or model:GetAttribute("HeroId") ~= id or model:GetAttribute("OwnerUserId") ~= player.UserId
		or not model:IsDescendantOf(workspace) then return end
	closeMenu(false)
	heroId = id
	selection = {Model = model, Token = token, Parent = model.Parent}
	local currentSelection = selection
	feedback.Text = ""
	rebuildMilestones()
	panel.Visible = true
	ancestryConnection = model.AncestryChanged:Connect(function()
		if selection ~= currentSelection then return end
		if model.Parent ~= currentSelection.Parent or not model:IsDescendantOf(workspace) then closeMenu(true) end
	end)
	render()
end)
closedUpgrade.OnClientEvent:Connect(function(token)
	if selection and selection.Token == token then closeMenu(false) end
end)
player.CharacterAdded:Connect(function() closeMenu(true) end)
for _, name in {"Gold", "GoldMultiplier", "HasCombatArea", "TotalDPS"} do
	player:GetAttributeChangedSignal(name):Connect(render)
end
for _, snapshot in heroSnapshots do
	snapshot.Data.AttributeChanged:Connect(render)
	snapshot.Upgrades.AttributeChanged:Connect(render)
	for _, mode in purchaseModes do
		snapshot.Quotes:WaitForChild(mode).AttributeChanged:Connect(render)
	end
end
modeButton.Activated:Connect(function()
	modeIndex = modeIndex % #purchaseModes + 1
	render()
end)
levelButton.Activated:Connect(function()
	local data = heroSnapshots[heroId].Data
	local gold = player:GetAttribute("Gold")
	if gold == nil then return end
	if data:GetAttribute("Owned") == true then
		local quote = heroSnapshots[heroId].Quotes[purchaseModes[modeIndex]]
		if (quote:GetAttribute("Count") or 0) > 0 and not data:GetAttribute("AtMaxLevel") then
			request(buyLevel, heroId, purchaseModes[modeIndex])
		end
	end
end)
local messages = {
	HeroPurchased = "Hero unlocked!", LevelPurchased = "Hero leveled up!",
	UpgradePurchased = "Upgrade purchased!", NotEnoughGold = "Not enough gold.",
	InvalidSelection = "Interact with your hero again.", MaxLevel = "Maximum prototype level reached.", InvalidPlayer = "Progression is not available.",
	InvalidMode = "Unknown purchase mode.", InvalidHero = "Unknown hero.", InvalidUpgrade = "Unknown upgrade.",
	Locked = "Required level not reached.", AlreadyPurchased = "Already purchased.",
	AlreadyOwned = "Hero already owned.", NotOwned = "Buy this hero first.",
}
local function purchaseResult(success, reason, count, cost, token)
	if not selection or selection.Token ~= token then return end
	feedback.Text = messages[reason] or "Purchase failed."
	if success and reason == "LevelPurchased" and count then
		feedback.Text = "+" .. tostring(count) .. " Levels · " .. NumberFormatter.Format(cost) .. " Gold spent"
	end
	feedback.TextColor3 = success and Color3.fromRGB(120, 230, 155) or Color3.fromRGB(245, 145, 135)
	render()
end
buyLevel.OnClientEvent:Connect(purchaseResult)
buyUpgrade.OnClientEvent:Connect(purchaseResult)
render()
gui.Parent = playerGui
require(script.Parent.GoldPopup).Start(gui)
require(script.Parent.CombatDebugPanel).Start(gui)
require(script.Parent.HeroPromptVisibility).Start()
