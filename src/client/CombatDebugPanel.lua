local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local CombatDebugPanel = {}
function CombatDebugPanel.Start(gui)
	if not RunService:IsStudio() or not GameConfig.StudioTesting.Enabled then return end
	local data = Players.LocalPlayer:WaitForChild("HeroCavesCombatDebug")
	local remote = ReplicatedStorage:WaitForChild("HeroCavesCombatDebug"):WaitForChild("Control")
	local panel = Instance.new("ScrollingFrame")
	panel.Name = "CombatDebug"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 84)
	panel.Size = UDim2.new(0, 320, 0.8, -84)
	panel.CanvasSize = UDim2.fromOffset(0, 780)
	panel.ScrollBarThickness = 6
	panel.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local function item(class, name, y, height)
		local obj = Instance.new(class)
		obj.Name = name
		obj.Position = UDim2.fromOffset(12, y)
		obj.Size = UDim2.new(1, -30, 0, height)
		obj.TextColor3 = Color3.fromRGB(235, 240, 250)
		obj.Font = Enum.Font.Gotham
		obj.TextSize = 14
		obj.TextWrapped = true
		obj.Parent = panel
		if class == "TextLabel" then
			obj.BackgroundTransparency = 1
			obj.TextXAlignment = Enum.TextXAlignment.Left
		else
			obj.BackgroundColor3 = Color3.fromRGB(55, 95, 145)
		end
		return obj
	end
	item("TextLabel", "Title", 6, 28).Text = "STUDIO · Your island combat"
	local context = item("TextLabel", "Context", 38, 90)
	local pause = item("TextButton", "Pause", 132, 32)
	local reset = item("TextButton", "ResetEnemyHP", 170, 32)
	reset.Text = "Reset current enemy HP"
	local labels, buttons = {}, {}
	local lastRequest = -math.huge
	local function request(...)
		if not data:GetAttribute("Active") then return end
		if time() - lastRequest < 0.15 then return end
		lastRequest = time()
		remote:FireServer(...)
	end
	pause.Activated:Connect(function() request("SetPaused", not data:GetAttribute("Paused")) end)
	reset.Activated:Connect(function() request("ResetEnemyHP") end)
	for index, id in HeroConfig.HeroOrder do
		local y = 212 + (index - 1) * 186
		labels[id] = item("TextLabel", id .. "Stats", y, 106)
		buttons[id] = item("TextButton", id .. "Toggle", y + 108, 32)
		local resetHero = item("TextButton", id .. "Reset", y + 146, 32)
		resetHero.Text = "RESET HERO · " .. id
		resetHero.Activated:Connect(function() request("ResetHero", id) end)
		local snapshot = data:WaitForChild(id)
		buttons[id].Activated:Connect(function()
			request("SetHeroEnabled", id, not snapshot:GetAttribute("Selected"))
		end)
	end
	local function render()
		context.Text = not data:GetAttribute("Active") and "NO ACTIVE COMBAT AREA\nClaim an island to start combat." or string.format("Wave %s · Boss %s\nEnemy %s / %s HP\nGold Multiplier: x%.2f · Total DPS: %s\nPlayer: %s",
			tostring(data:GetAttribute("Wave")), data:GetAttribute("IsBoss") and "Yes" or "No",
			NumberFormatter.Format(data:GetAttribute("EnemyHP")), NumberFormatter.Format(data:GetAttribute("EnemyMaxHP")),
			data:GetAttribute("GoldMultiplier") or 1, NumberFormatter.Format(data:GetAttribute("TotalDPS")),
			tostring(data:GetAttribute("OwnerUserId")))
		pause.Text = data:GetAttribute("Paused") and "Resume ALL hero attacks" or "Pause ALL hero attacks"
		for _, id in HeroConfig.HeroOrder do
			local snapshot = data[id]
			local owned = snapshot:GetAttribute("Owned") == true
			labels[id].Text = string.format("%s · %s\nLevel %s · Damage %s\nInterval %.3fs · Speed %.2f attacks/s\nDPS %s · Attacks %s", id, owned and "Owned" or "Not owned",
				tostring(snapshot:GetAttribute("Level")), NumberFormatter.Format(snapshot:GetAttribute("Damage")),
				snapshot:GetAttribute("AttackInterval") or 0, snapshot:GetAttribute("AttackSpeed") or 0,
				NumberFormatter.Format(snapshot:GetAttribute("DPS")), snapshot:GetAttribute("AttackEnabled") and "Enabled" or "Disabled")
			buttons[id].Text = id .. " attacks " .. (snapshot:GetAttribute("Selected") and "ON" or "OFF")
		end
	end
	data.AttributeChanged:Connect(render)
	for _, id in HeroConfig.HeroOrder do data[id].AttributeChanged:Connect(render) end
	render()
end
return CombatDebugPanel
