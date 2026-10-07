local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local NumberFormatter = require(ReplicatedStorage.Shared.NumberFormatter)

local GoldPopup = {}
function GoldPopup.Start(gui)
	local event = ReplicatedStorage:WaitForChild("IdleHeroSimulatorGoldAwarded")
	local popups = {}
	event.OnClientEvent:Connect(function(amount)
		if type(amount) ~= "number" or amount <= 0 or amount ~= amount or amount == math.huge then return end
		-- Bound concurrent notifications during fast waves; no client reward formula.
		if #popups >= 5 then table.remove(popups, 1):Destroy() end
		local popup = Instance.new("TextLabel")
		popup.Name = "GoldGain"
		popup.AnchorPoint = Vector2.new(0.5, 0.5)
		popup.Position = UDim2.new(0.5, 0, 0.3, #popups * 30)
		popup.Size = UDim2.fromOffset(240, 30)
		popup.BackgroundTransparency = 1
		popup.TextColor3 = Color3.fromRGB(255, 215, 90)
		popup.TextStrokeTransparency = 0.4
		popup.Font = Enum.Font.GothamBold
		popup.TextSize = 22
		popup.Text = "+" .. NumberFormatter.Format(amount) .. " Gold"
		popup.Parent = gui
		table.insert(popups, popup)
		local tween = TweenService:Create(popup,
			TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0.8), {
				Position = UDim2.new(0.5, 0, 0.3, (#popups - 1) * 30 - 40),
				TextTransparency = 1, TextStrokeTransparency = 1,
			})
		tween.Completed:Connect(function()
			local index = table.find(popups, popup)
			if index then table.remove(popups, index) end
			popup:Destroy()
		end)
		tween:Play()
	end)
end
return GoldPopup
