local Players = game:GetService("Players")
local HeroPromptVisibility = {}
local started = {}

function HeroPromptVisibility.IsOwner(hero, userId)
	return hero ~= nil and hero:IsA("Model") and hero:GetAttribute("OwnerUserId") == userId
		and type(hero:GetAttribute("HeroId")) == "string"
		and type(hero:GetAttribute("ContextId")) == "string"
end

function HeroPromptVisibility.Start()
	local player = Players.LocalPlayer
	if started[player] then return end
	started[player] = true
	local watched = {}
	local function track(prompt)
		-- Only the physical hero interaction: never the shared Hero Shop prompt.
		if not prompt:IsA("ProximityPrompt") or prompt.Name ~= "UpgradeHero" or watched[prompt] then return end
		local connections, ownerConnections = {}, {}
		local hero
		local function disconnect(list)
			for _, connection in list do connection:Disconnect() end
			table.clear(list)
		end
		local function refresh()
			local enabled = HeroPromptVisibility.IsOwner(hero, player.UserId)
			if prompt.Enabled ~= enabled then prompt.Enabled = enabled end
		end
		local function bindOwner()
			local nextHero = prompt:FindFirstAncestorOfClass("Model")
			if nextHero ~= hero then
				disconnect(ownerConnections)
				hero = nextHero
				if hero then
					for _, attribute in {"OwnerUserId", "HeroId", "ContextId"} do
						table.insert(ownerConnections, hero:GetAttributeChangedSignal(attribute):Connect(refresh))
					end
				end
			end
			refresh()
		end
		watched[prompt] = true
		table.insert(connections, prompt.AncestryChanged:Connect(function()
			if not prompt:IsDescendantOf(workspace) then
				disconnect(connections)
				disconnect(ownerConnections)
				watched[prompt] = nil
				return
			end
			bindOwner()
		end))
		-- Reapply if server replication updates Enabled after the local filter.
		table.insert(connections, prompt:GetPropertyChangedSignal("Enabled"):Connect(refresh))
		bindOwner()
	end
	-- Subscribe before the one startup scan; later claims/purchases/reuse are event-driven.
	workspace.DescendantAdded:Connect(track)
	for _, instance in workspace:GetDescendants() do track(instance) end
end

return HeroPromptVisibility
