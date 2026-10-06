local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local NumberFormatter = require(Shared:WaitForChild("NumberFormatter"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local buyLevel = ReplicatedStorage:WaitForChild("HeroCavesRemotes"):WaitForChild("BuyKnightLevel")

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
panel.Size = UDim2.fromOffset(300, 285)
panel.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
panel.BorderSizePixel = 0
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local function label(name, y, height, fontSize)
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
	text.Parent = panel
	return text
end

local goldLabel = label("Gold", 12, 36, 24)
goldLabel.TextColor3 = Color3.fromRGB(240, 205, 90)
local title = label("Knight", 53, 25, 19)
title.Text = "KNIGHT · Your progression"
local levelLabel = label("Level", 83, 24, 18)
local damageLabel = label("Damage", 110, 24, 18)
local button = Instance.new("TextButton")
button.Name = "LevelUp"
button.Position = UDim2.fromOffset(16, 146)
button.Size = UDim2.new(1, -32, 0, 42)
button.Font = Enum.Font.GothamBold
button.TextSize = 17
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.BorderSizePixel = 0
button.Parent = panel
local feedback = label("PurchaseResult", 192, 24, 14)
feedback.Text = ""
local ownerLabel = label("CombatOwner", 221, 52, 13)
ownerLabel.TextColor3 = Color3.fromRGB(180, 190, 210)

local function render()
	local gold = player:GetAttribute("Gold")
	local level = player:GetAttribute("KnightLevel")
	local damage = player:GetAttribute("KnightDamage")
	local cost = player:GetAttribute("KnightNextLevelCost")
	local maxLevel = player:GetAttribute("KnightAtMaxLevel")
	local ready = gold ~= nil and level ~= nil and damage ~= nil and cost ~= nil
	local affordable = ready and not maxLevel and gold >= cost
	goldLabel.Text = "GOLD: " .. NumberFormatter.Format(gold)
	levelLabel.Text = "Level " .. NumberFormatter.Format(level)
	damageLabel.Text = "Damage: " .. NumberFormatter.Format(damage)
	button.Text = not ready and "Loading..." or (maxLevel and "Maximum level"
		or ("Level Up — " .. NumberFormatter.Format(cost) .. " Gold"))
	button.Active = affordable
	button.AutoButtonColor = affordable
	button.BackgroundColor3 = affordable and Color3.fromRGB(50, 130, 85) or Color3.fromRGB(75, 80, 90)
	if player:GetAttribute("IsKnightCombatOwner") then
		ownerLabel.Text = "The shared Knight uses your level and damage."
	else
		ownerLabel.Text = "Shared Knight uses another player's levels. Your purchases remain personal."
	end
end

for _, name in {"Gold", "KnightLevel", "KnightDamage", "KnightNextLevelCost",
	"KnightAtMaxLevel", "IsKnightCombatOwner"} do
	player:GetAttributeChangedSignal(name):Connect(render)
end
local lastRequestAt = -math.huge
button.Activated:Connect(function()
	local gold = player:GetAttribute("Gold")
	local cost = player:GetAttribute("KnightNextLevelCost")
	if gold == nil or cost == nil or gold < cost or player:GetAttribute("KnightAtMaxLevel") then
		return
	end
	if time() - lastRequestAt < GameConfig.Economy.PurchaseCooldown then
		return
	end
	lastRequestAt = time()
	-- No price, level or damage is sent to the server.
	buyLevel:FireServer()
end)
local messages = {
	Purchased = "Knight leveled up!",
	NotEnoughGold = "Not enough gold.",
	MaxLevel = "Maximum prototype level reached.",
	InvalidPlayer = "Progression is not available.",
}
buyLevel.OnClientEvent:Connect(function(success, reason)
	feedback.Text = messages[reason] or "Purchase failed."
	feedback.TextColor3 = success and Color3.fromRGB(120, 230, 155) or Color3.fromRGB(245, 145, 135)
	render()
end)
render()
gui.Parent = playerGui
