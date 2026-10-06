local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EnemyService = require(script.Parent.EnemyService)
local CombatService = require(script.Parent.CombatService)
local ProgressionService = require(script.Parent.ProgressionService)
local KnightRig = require(script.Parent.Parent.Heroes.KnightRig)
local RangedRig = require(script.Parent.Parent.Heroes.RangedRig)

local CombatDebugState = require(script.Parent.CombatDebugState)

local HeroService = {}
local activeHeroes = {}
local heroesById = {}
local connection = nil
local heroFolder = nil
local debugConnection = nil
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
	local owner = ProgressionService.GetCombatOwner()
	if hero.Owner ~= owner then
		idle(hero)
		return
	end
	if not owner then
		return
	end
	if not CombatDebugState.IsHeroEnabled(hero.Id) then
		if hero.Target then idle(hero) end
		return
	end
	hero.Model:SetAttribute("Level", ProgressionService.GetHeroLevel(owner, hero.Id))
	hero.Model:SetAttribute("Damage", ProgressionService.GetHeroDamage(owner, hero.Id, false))
	local target = EnemyService.GetActiveEnemy()
	if not target or not target.Model.Parent or target.Health <= 0
		or (target.IsBoss and now >= target.Deadline) then
		if hero.Target then
			idle(hero)
		end
		return
	end

	local enemyPosition = target.Model.PrimaryPart.Position
	-- Each hero definition owns its slot offset; no chasing or pathfinding.
	hero.Rig:SetFacing(GameConfig.EnemySpawnPosition + hero.Config.SlotOffset, enemyPosition)
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
				(elapsed - animation.WindupDuration) / animation.SwingDuration)
		end
	else
		if not hero.Impacted then
			-- Pose is replicated before the single authoritative hit is applied.
			hero.Rig:SetPose(animation.ImpactAngle)
			if hero.Rig.SetProjectileProgress then
				hero.Rig:SetProjectileProgress(enemyPosition, 1)
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

function HeroService.GetActiveHeroes()
	return table.clone(activeHeroes)
end

local function synchronizeOwnedHeroes(owner, now)
	for index = #activeHeroes, 1, -1 do
		local hero = activeHeroes[index]
		if hero.Owner ~= owner or not ProgressionService.OwnsHero(owner, hero.Id) or not hero.Model.Parent then
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
			local rig = factory(config, heroFolder)
			rig:SetFacing(GameConfig.EnemySpawnPosition + config.SlotOffset, GameConfig.EnemySpawnPosition)
			local hero = {Id = heroId, Config = config, Rig = rig, Model = rig.Model,
				Owner = owner, NextAttackAt = now}
			hero.Model:SetAttribute("OwnerUserId", owner.UserId)
			idle(hero)
			heroesById[heroId] = hero
			table.insert(activeHeroes, hero)
			if GameConfig.DebugLogging then
				print("[HeroService] Spawned " .. config.Name .. "; independent combat active")
			end
		end
	end
end

function HeroService.Start()
	if connection then
		return
	end
	debugConnection = CombatDebugState.Changed:Connect(function()
		for _, hero in activeHeroes do
			if not CombatDebugState.IsHeroEnabled(hero.Id) then idle(hero) end
		end
	end)
	heroFolder = Instance.new("Folder")
	heroFolder.Name = "HeroCavesHeroes"
	heroFolder.Parent = workspace
	synchronizeOwnedHeroes(ProgressionService.GetCombatOwner(), time())
	connection = RunService.Heartbeat:Connect(function()
		local now = time()
		synchronizeOwnedHeroes(ProgressionService.GetCombatOwner(), now)
		-- One dispatcher; each hero owns its own attack start, cooldown and projectile.
		for _, activeHero in activeHeroes do
			updateHero(activeHero, now)
		end
	end)
end

function HeroService.Stop()
	if debugConnection then debugConnection:Disconnect(); debugConnection = nil end
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, hero in activeHeroes do
		hero.Rig:Destroy()
	end
	table.clear(activeHeroes)
	table.clear(heroesById)
	if heroFolder then
		heroFolder:Destroy()
		heroFolder = nil
	end
end

return HeroService
