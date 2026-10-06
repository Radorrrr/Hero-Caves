local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeroConfig = require(ReplicatedStorage.Shared.HeroConfig)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EnemyService = require(script.Parent.EnemyService)
local CombatService = require(script.Parent.CombatService)
local ProgressionService = require(script.Parent.ProgressionService)
local KnightRig = require(script.Parent.Parent.Heroes.KnightRig)

local HeroService = {}
local activeHeroes = {}
local connection = nil
local heroFolder = nil
local rigFactories = {Knight = KnightRig.new}

local function interpolate(from, to, progress)
	local eased = TweenService:GetValue(math.clamp(progress, 0, 1),
		Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	return from + (to - from) * eased
end

local function idle(hero)
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
		hero.Owner = owner
		hero.Model:SetAttribute("OwnerUserId", owner and owner.UserId or 0)
	end
	if not owner then
		return
	end
	hero.Model:SetAttribute("Level", ProgressionService.GetKnightLevel(owner))
	hero.Model:SetAttribute("Damage", ProgressionService.GetKnightDamage(owner))
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
		hero.NextAttackAt = now + math.max(hero.Config.AttackInterval, animationEnd)
		hero.Impacted = false
	end

	local elapsed = now - hero.AttackStartedAt
	if elapsed < animation.WindupDuration then
		hero.Model:SetAttribute("AttackPhase", "Windup")
		hero.Rig:SetPose(interpolate(animation.IdleAngle, animation.WindupAngle,
			elapsed / animation.WindupDuration))
	elseif elapsed < impactAt then
		hero.Model:SetAttribute("AttackPhase", "Swing")
		hero.Rig:SetPose(interpolate(animation.WindupAngle, animation.ImpactAngle,
			(elapsed - animation.WindupDuration) / animation.SwingDuration))
	else
		if not hero.Impacted then
			-- Pose is replicated before the single authoritative hit is applied.
			hero.Rig:SetPose(animation.ImpactAngle)
			hero.Model:SetAttribute("AttackPhase", "Impact")
			hero.Impacted = true
			CombatService.DamageEnemy(hero, hero.Target)
			-- On a long frame, still show the impact pose for this update.
			return
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

function HeroService.Start()
	if connection then
		return
	end
	local config = HeroConfig.Knight
	assert(config.AttackInterval > 0 and config.BaseDamage > 0, "Invalid Knight combat configuration")
	local animation = config.Animation
	for _, duration in {animation.WindupDuration, animation.SwingDuration,
		animation.FollowThroughDuration, animation.RecoveryDuration} do
		assert(duration > 0, "Animation durations must be positive")
	end
	heroFolder = Instance.new("Folder")
	heroFolder.Name = "HeroCavesHeroes"
	heroFolder.Parent = workspace
	local rig = rigFactories.Knight(config, heroFolder)
	rig:SetFacing(GameConfig.EnemySpawnPosition + config.SlotOffset, GameConfig.EnemySpawnPosition)
	local hero = {Id = "Knight", Config = config, Rig = rig, Model = rig.Model, NextAttackAt = time()}
	idle(hero)
	table.insert(activeHeroes, hero)
	connection = RunService.Heartbeat:Connect(function()
		local now = time()
		for _, activeHero in activeHeroes do
			updateHero(activeHero, now)
		end
	end)
	if GameConfig.DebugLogging then
		print("[HeroService] Spawned Knight; procedural combat active")
	end
end

function HeroService.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, hero in activeHeroes do
		hero.Rig:Destroy()
	end
	table.clear(activeHeroes)
	if heroFolder then
		heroFolder:Destroy()
		heroFolder = nil
	end
end

return HeroService
