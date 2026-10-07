local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EnemyConfig = require(ReplicatedStorage.Shared.EnemyConfig)
local ProgressionMath = require(script.Parent.Parent.ProgressionMath)

local EnemyService = {}
local defeatedEvent = Instance.new("BindableEvent")
EnemyService.Defeated = defeatedEvent.Event
local changedEvent = Instance.new("BindableEvent")
EnemyService.Changed = changedEvent.Event
local Contexts = require(script.Parent.CombatContexts)

local function normalHealth(wave)
	return math.floor(EnemyConfig.BaseHealth * EnemyConfig.HealthGrowth ^ (wave - 1) + 0.5)
end

local function updateDisplay(enemy)
	enemy.Model:SetAttribute("Health", enemy.Health)
	enemy.HealthLabel.Text = string.format("%d / %d HP", enemy.Health, enemy.MaxHealth)
	enemy.HealthFill.Size = UDim2.fromScale(enemy.Health / enemy.MaxHealth, 1)
	if enemy.IsBoss then
		local remaining = math.max(0, math.ceil(enemy.Deadline - time()))
		enemy.Model:SetAttribute("TimeRemaining", remaining)
		enemy.NameLabel.Text = string.format("[BOSS] %s · %ds", enemy.Name, remaining)
	else
		enemy.NameLabel.Text = enemy.Name
	end
end

function EnemyService.GetActiveEnemy(context)
	return Contexts.IsActive(context) and context.CurrentEnemy or nil
end

function EnemyService.Remove(context)
	if context and context.CurrentEnemy then
		context.CurrentEnemy.Model:Destroy()
		context.CurrentEnemy = nil
		changedEvent:Fire(context.Player, context.Id)
	end
end

function EnemyService.Spawn(context, wave, isBoss)
	if not Contexts.IsActive(context) then return nil end
	EnemyService.Remove(context)
	context.EnemySequence += 1

	local definition = isBoss and EnemyConfig.Boss or EnemyConfig.Normal
	local maxHealth = isBoss
		and normalHealth(wave - 1) * EnemyConfig.BossHealthMultiplier
		or normalHealth(wave)
	local model = Instance.new("Model")
	model.Name = definition.Name
	model:SetAttribute("OwnerUserId", context.Player.UserId)
	model:SetAttribute("ContextId", context.Id)
	model:SetAttribute("EnemyId", context.Id .. ":" .. context.EnemySequence)
	model:SetAttribute("Wave", wave)
	model:SetAttribute("IsBoss", isBoss)
	model:SetAttribute("MaxHealth", maxHealth)
	local goldReward = ProgressionMath.GetGoldReward(wave, isBoss)
	model:SetAttribute("GoldReward", goldReward)

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = definition.Size
	body.Color = definition.Color
	body.Material = Enum.Material.SmoothPlastic
	body.CFrame = context.Island.Markers.EnemyPosition.CFrame
	body.Anchored = true
	body.CanCollide = false
	body.Parent = model
	model.PrimaryPart = body

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthDisplay"
	billboard.Size = UDim2.fromOffset(240, 80)
	billboard.StudsOffset = Vector3.new(0, definition.Size.Y / 2 + 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = body
	billboard.Parent = body

	local function label(name, y)
		local text = Instance.new("TextLabel")
		text.Name = name
		text.Position = UDim2.fromOffset(0, y)
		text.Size = UDim2.new(1, 0, 0, 25)
		text.BackgroundTransparency = 1
		text.TextColor3 = Color3.fromRGB(255, 255, 255)
		text.TextStrokeTransparency = 0.4
		text.Font = Enum.Font.GothamBold
		text.TextSize = 18
		text.Parent = billboard
		return text
	end

	local nameLabel = label("EnemyName", 0)
	local healthLabel = label("Health", 27)
	local bar = Instance.new("Frame")
	bar.Name = "HealthBar"
	bar.Position = UDim2.new(0, 10, 0, 58)
	bar.Size = UDim2.new(1, -20, 0, 14)
	bar.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	bar.BorderSizePixel = 0
	bar.Parent = billboard
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = definition.Color
	fill.BorderSizePixel = 0
	fill.Parent = bar

	local enemy = {
		Context = context,
		Sequence = context.EnemySequence,
		Model = model,
		Name = definition.Name,
		Health = maxHealth,
		MaxHealth = maxHealth,
		IsBoss = isBoss,
		Wave = wave,
		GoldReward = goldReward,
		Deadline = isBoss and (time() + GameConfig.BossTimeLimit) or nil,
		NameLabel = nameLabel,
		HealthLabel = healthLabel,
		HealthFill = fill,
	}
	context.CurrentEnemy = enemy
	updateDisplay(enemy)
	model.Parent = context.EnemyFolder
	changedEvent:Fire(context.Player, context.Id)
	if GameConfig.DebugLogging then
		print(string.format("[EnemyService] Spawned %s with %d HP", definition.Name, maxHealth))
	end
	return enemy
end

function EnemyService.UpdateDisplay(context)
	local enemy = EnemyService.GetActiveEnemy(context)
	if enemy and enemy.IsBoss then
		local remaining = math.max(0, math.ceil(enemy.Deadline - time()))
		if enemy.Model:GetAttribute("TimeRemaining") ~= remaining then
			updateDisplay(enemy)
			changedEvent:Fire(context.Player, context.Id) -- Timer snapshot only when its displayed second changes.
		end
	end
end

function EnemyService.Damage(context, amount, sourceName)
	local enemy = EnemyService.GetActiveEnemy(context)
	if not enemy or type(amount) ~= "number" or amount <= 0
		or amount ~= amount or amount == math.huge then
		return false
	end
	-- Damage at or after the deadline cannot turn a failed boss into a victory.
	if enemy.IsBoss and time() >= enemy.Deadline then
		return false
	end
	enemy.Health = math.max(0, enemy.Health - math.floor(amount))
	updateDisplay(enemy)
	changedEvent:Fire(context.Player, context.Id)
	if GameConfig.DebugLogging then
		print(string.format("[CombatService] %s dealt %d damage", sourceName or "Server", math.floor(amount)))
	end
	if enemy.Health == 0 then
		if GameConfig.DebugLogging then
			print("[EnemyService] Enemy defeated")
		end
		EnemyService.Remove(context)
		-- Removal for replacement/timeout never fires this death-only signal.
		-- Keep authoritative reward data in the private context; events carry only stable handles.
		context.PendingRewards[enemy.Sequence] = enemy.GoldReward
		defeatedEvent:Fire(context.Player, context.Id, enemy.Sequence)
	end
	return true
end

-- Server-only HP reset. Boss deadline deliberately continues to run.
function EnemyService.ResetHealth(context)
	local enemy = EnemyService.GetActiveEnemy(context)
	if not enemy or enemy.Health <= 0 or (enemy.IsBoss and time() >= enemy.Deadline) then return false end
	enemy.Health = enemy.MaxHealth
	updateDisplay(enemy)
	changedEvent:Fire(context.Player, context.Id)
	return true
end

return EnemyService
