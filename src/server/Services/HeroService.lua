local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EnemyService = require(script.Parent.EnemyService)
local CombatService = require(script.Parent.CombatService)
local ProgressionService = require(script.Parent.ProgressionService)
local HeroUpgradeService = require(script.Parent.HeroUpgradeService)
local KnightRig = require(script.Parent.Parent.Heroes.KnightRig)
local RangedRig = require(script.Parent.Parent.Heroes.RangedRig)

local CombatDebugState = require(script.Parent.CombatDebugState)

local HeroService = {}
local Contexts = require(script.Parent.CombatContexts)
local rigFactories = {Knight = KnightRig.new, Ranged = RangedRig.new}

local function interpolate(from, to, progress)
	local eased = TweenService:GetValue(math.clamp(progress, 0, 1),
		Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	return from + (to - from) * eased
end

local function idle(hero)
	if hero.Rig.ClearProjectile then
		hero.Rig:ClearProjectile()
	end
	hero.Target = nil
	hero.AttackStartedAt = nil
	hero.Impacted = false
	hero.Rig:SetPose(hero.Config.Animation.IdleAngle)
	hero.Model:SetAttribute("AttackPhase", "Idle")
end

local function updateHero(hero, now)
	local context = hero.Context
	local owner = hero.Owner
	if not Contexts.IsActive(context) or not CombatDebugState.IsHeroEnabled(owner, hero.Id) then
		if hero.Target then idle(hero) end
		return
	end
	hero.Model:SetAttribute("Level", ProgressionService.GetHeroLevel(owner, hero.Id))
	hero.Model:SetAttribute("Damage", ProgressionService.GetHeroDamage(owner, hero.Id, false))
	local target = EnemyService.GetActiveEnemy(context)
	if not target or not target.Model.Parent or target.Health <= 0
		or (target.IsBoss and now >= target.Deadline) then
		if hero.Target then
			idle(hero)
		end
		return
	end

	local enemyPosition = target.Model.PrimaryPart.Position
	-- The claimed island provides the slot; no chasing or pathfinding.
	hero.Rig:SetFacing(context.Island.Markers[hero.Id .. "Slot"].Position, enemyPosition)
	if hero.Target and hero.Target ~= target then
		idle(hero)
	end
	local animation = hero.Config.Animation
	local impactAt = animation.WindupDuration + animation.SwingDuration
	local followThroughEnd = impactAt + animation.FollowThroughDuration
	local animationEnd = followThroughEnd + animation.RecoveryDuration
	if not hero.AttackStartedAt then
		if now < hero.NextAttackAt then
			return
		end
		hero.Target = target
		hero.AttackStartedAt = now
		local interval = ProgressionService.GetHeroAttackInterval(owner, hero.Id)
		-- Scale the pose timeline too, so faster attacks keep their impact in sync.
		hero.AnimationSpeed = hero.Config.AttackInterval / interval
		hero.NextAttackAt = now + math.max(interval, animationEnd / hero.AnimationSpeed)
		hero.Impacted = false
	end

	local elapsed = (now - hero.AttackStartedAt) * hero.AnimationSpeed
	if elapsed < animation.WindupDuration then
		hero.Model:SetAttribute("AttackPhase", "Windup")
		hero.Rig:SetPose(interpolate(animation.IdleAngle, animation.WindupAngle,
			elapsed / animation.WindupDuration))
	elseif elapsed < impactAt then
		hero.Model:SetAttribute("AttackPhase", "Swing")
		hero.Rig:SetPose(interpolate(animation.WindupAngle, animation.ImpactAngle,
			(elapsed - animation.WindupDuration) / animation.SwingDuration))
		if hero.Rig.SetProjectileProgress then
			hero.Rig:SetProjectileProgress(enemyPosition,
				(elapsed - animation.WindupDuration) / animation.SwingDuration, hero.Target)
		end
	else
		if not hero.Impacted then
			-- Pose is replicated before the single authoritative hit is applied.
			hero.Rig:SetPose(animation.ImpactAngle)
			if hero.Rig.SetProjectileProgress then
				hero.Rig:SetProjectileProgress(enemyPosition, 1, hero.Target)
			end
			hero.Model:SetAttribute("AttackPhase", "Impact")
			hero.Impacted = true
			CombatService.DamageEnemy(hero, hero.Target)
			-- On a long frame, still show the impact pose for this update.
			return
		end
		if hero.Rig.ClearProjectile then
			hero.Rig:ClearProjectile()
		end
		if elapsed < followThroughEnd then
			hero.Model:SetAttribute("AttackPhase", "FollowThrough")
			hero.Rig:SetPose(interpolate(animation.ImpactAngle, animation.FollowThroughAngle,
				(elapsed - impactAt) / animation.FollowThroughDuration))
		elseif elapsed < animationEnd then
			hero.Model:SetAttribute("AttackPhase", "Recovery")
			hero.Rig:SetPose(interpolate(animation.FollowThroughAngle, animation.IdleAngle,
				(elapsed - followThroughEnd) / animation.RecoveryDuration))
		else
			idle(hero)
		end
	end
end

function HeroService.GetActiveHeroes(context)
	return context and table.clone(context.Heroes) or {}
end

local function synchronizeOwnedHeroes(context, now)
	local owner = context.Player
	local activeHeroes, heroesById = context.Heroes, context.HeroesById
	for index = #activeHeroes, 1, -1 do
		local hero = activeHeroes[index]
		if hero.Owner ~= owner or not ProgressionService.OwnsHero(owner, hero.Id)
			or not hero.Model:IsDescendantOf(context.HeroFolder) then
			HeroUpgradeService.Detach(hero)
			hero.Rig:Destroy()
			heroesById[hero.Id] = nil
			table.remove(activeHeroes, index)
		end
	end
	if not owner then return end
	for _, heroId in HeroConfig.HeroOrder do
		if ProgressionService.OwnsHero(owner, heroId) and not heroesById[heroId] then
			local config = HeroConfig[heroId]
			assert(config.AttackInterval > 0 and config.BaseDamage > 0, "Invalid hero combat configuration")
			local animation = config.Animation
			for _, duration in {animation.WindupDuration, animation.SwingDuration,
				animation.FollowThroughDuration, animation.RecoveryDuration} do
				assert(duration > 0, "Animation durations must be positive")
			end
			local factory = rigFactories[config.RigType]
			assert(factory, "No rig factory for hero")
			local rig = factory(config, context.HeroFolder)
			rig:SetFacing(context.Island.Markers[heroId .. "Slot"].Position, context.Island.Markers.EnemyPosition.Position)
			local hero = {Id = heroId, Config = config, Rig = rig, Model = rig.Model,
				Owner = owner, Context = context, NextAttackAt = now}
			hero.Model:SetAttribute("OwnerUserId", owner.UserId)
			hero.Model:SetAttribute("ContextId", context.Id)
			idle(hero)
			heroesById[heroId] = hero
			table.insert(activeHeroes, hero)
			HeroUpgradeService.Attach(hero)
			if GameConfig.DebugLogging then
				print("[HeroService] Spawned " .. config.Name .. "; independent combat active")
			end
		end
	end
end

function HeroService.RefreshOwnedHeroes(context)
	if Contexts.IsActive(context) then synchronizeOwnedHeroes(context, time()) end
end

function HeroService.Start(context)
	if not Contexts.IsActive(context) or context.HeroConnection then return end
	table.insert(context.HeroConnections, ProgressionService.HeroReset:Connect(function(player, heroId)
		if player ~= context.Player then return end
		local hero = context.HeroesById[heroId]
		if hero then idle(hero); hero.NextAttackAt = time() end
	end))
	table.insert(context.HeroConnections, CombatDebugState.Changed:Connect(function(player)
		if player ~= context.Player then return end
		for _, hero in context.Heroes do
			if not CombatDebugState.IsHeroEnabled(player, hero.Id) then idle(hero) end
		end
	end))
	table.insert(context.HeroConnections, EnemyService.Changed:Connect(function(player, contextId)
		if player ~= context.Player or contextId ~= context.Id then return end
		for _, hero in context.Heroes do
			if hero.Target and hero.Target ~= context.CurrentEnemy then idle(hero) end
		end
	end))
	synchronizeOwnedHeroes(context, time())
	context.HeroConnection = RunService.Heartbeat:Connect(function()
		if not Contexts.IsActive(context) then return end
		synchronizeOwnedHeroes(context, time())
		for _, hero in context.Heroes do updateHero(hero, time()) end
	end)
end
function HeroService.Stop(context)
	if context.HeroConnection then context.HeroConnection:Disconnect(); context.HeroConnection = nil end
	for _, connection in context.HeroConnections do connection:Disconnect() end
	table.clear(context.HeroConnections)
	for _, hero in context.Heroes do HeroUpgradeService.Detach(hero); idle(hero); hero.Rig:Destroy() end
	table.clear(context.Heroes)
	table.clear(context.HeroesById)
end
return HeroService
