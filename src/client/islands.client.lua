local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local gui = Instance.new("ScreenGui")
gui.Name = "IdleHeroesIslandFeedback"
gui.ResetOnSpawn = false
gui.DisplayOrder = 15
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
if playerGui:FindFirstChild(gui.Name) then gui:Destroy(); return end
local label = Instance.new("TextLabel")
label.Name = "Message"
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 16)
label.Size = UDim2.new(0.45, 0, 0, 64)
label.BackgroundColor3 = Color3.fromRGB(30, 40, 50)
label.BackgroundTransparency = 0.2
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.Font = Enum.Font.GothamBold
label.TextSize = 18
label.TextWrapped = true
label.Visible = false
label.Parent = gui
gui.Parent = playerGui
local revision = 0
ReplicatedStorage:WaitForChild("IdleHeroesIslandFeedback").OnClientEvent:Connect(function(message)
	if type(message) ~= "string" then return end
	revision += 1
	local current = revision
	label.Text = message
	label.Visible = true
	task.delay(3, function()
		if revision == current then label.Visible = false end
	end)
end)
