local RangedRig = {}
RangedRig.__index = RangedRig

function RangedRig.new(config, parent)
	local self = setmetatable({}, RangedRig)
	self.Config = config
	self.Scale = config.Visual.Scale
	self.StaticParts = {}
	self.ArmParts = {}
	self.Angle = config.Animation.IdleAngle
	local visual = config.Visual
	local model = Instance.new("Model")
	model.Name = config.Name
	model:SetAttribute("HeroId", config.HeroId)
	self.Model = model
	local body = Instance.new("Folder")
	body.Name = "Body"
	body.Parent = model
	local arm = Instance.new("Folder")
	arm.Name = "WeaponArm"
	arm.Parent = model
	local weapon = Instance.new("Folder")
	weapon.Name = config.CombatStyle == "Bow" and "Bow" or "Staff"
	weapon.Parent = arm

	local function part(name, size, offset, color, container, entries, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * self.Scale
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Parent = container
		table.insert(entries, {Part = p, Offset = CFrame.new(offset * self.Scale)})
		return p
	end
	local function clothing(name, size, offset, color)
		return part(name, size, offset, color or visual.ClothColor, body, self.StaticParts)
	end
	local root = clothing("Root", Vector3.new(0.2, 0.2, 0.2), Vector3.zero)
	root.Transparency = 1
	model.PrimaryPart = root
	clothing("Torso", Vector3.new(1.65, 1.9, 0.9), Vector3.zero)
	clothing("Belt", Vector3.new(1.75, 0.2, 1), Vector3.new(0, -0.7, 0), visual.TrimColor)
	clothing("Head", Vector3.new(1.05, 1.05, 1.05), Vector3.new(0, 1.55, 0), visual.SkinColor)
	clothing("Eyes", Vector3.new(0.65, 0.1, 0.08), Vector3.new(0, 1.65, -0.56), Color3.fromRGB(25, 25, 30))
	clothing("LeftArm", Vector3.new(0.55, 1.6, 0.65), Vector3.new(-1.1, -0.15, 0))
	for _, side in {-1, 1} do
		local prefix = side == -1 and "Left" or "Right"
		clothing(prefix .. "Leg", Vector3.new(0.65, 1.25, 0.7), Vector3.new(side * 0.45, -1.45, 0))
		clothing(prefix .. "Boot", Vector3.new(0.75, 0.6, 1.1), Vector3.new(side * 0.45, -2.1, -0.2), visual.TrimColor)
	end
	part("RightArm", Vector3.new(0.55, 1.6, 0.65), Vector3.new(0, -0.8, 0),
		visual.ClothColor, arm, self.ArmParts)
	part("Hand", Vector3.new(0.6, 0.35, 0.6), Vector3.new(0, -1.55, 0),
		visual.SkinColor, arm, self.ArmParts)

	if config.CombatStyle == "Bow" then
		clothing("HoodTop", Vector3.new(1.25, 0.35, 1.2), Vector3.new(0, 2.15, 0))
		clothing("HoodBack", Vector3.new(1.25, 1.1, 0.2), Vector3.new(0, 1.65, 0.6))
		clothing("Quiver", Vector3.new(0.5, 1.7, 0.5), Vector3.new(-0.45, 0.3, 0.75), visual.TrimColor)
		-- A lightweight bent bow silhouette plus a visible string.
		for _, segment in {{0, -1.55}, {0.22, -1.0}, {0.22, -2.1}} do
			part("BowLimb", Vector3.new(0.18, 0.75, 0.2), Vector3.new(segment[1], segment[2], 0),
				visual.TrimColor, weapon, self.ArmParts, Enum.Material.Wood)
		end
		part("BowString", Vector3.new(0.05, 1.8, 0.05), Vector3.new(-0.18, -1.55, 0),
			Color3.fromRGB(230, 225, 200), weapon, self.ArmParts)
	else
		clothing("Robe", Vector3.new(1.75, 1.1, 1.0), Vector3.new(0, -1.0, 0))
		clothing("HatBrim", Vector3.new(1.9, 0.2, 1.55), Vector3.new(0, 2.1, 0))
		clothing("HatCrown", Vector3.new(0.95, 0.95, 0.95), Vector3.new(0, 2.65, 0))
		part("StaffShaft", Vector3.new(0.18, 3.2, 0.18), Vector3.new(0, -1.1, 0),
			visual.TrimColor, weapon, self.ArmParts, Enum.Material.Wood)
		local orb = part("StaffOrb", Vector3.new(0.65, 0.65, 0.65), Vector3.new(0, -2.85, 0),
			visual.ProjectileColor, weapon, self.ArmParts, Enum.Material.Neon)
		orb.Shape = Enum.PartType.Ball
	end
	local muzzleOffset = config.CombatStyle == "Bow" and Vector3.new(0, -1.55, 0)
		or Vector3.new(0, -2.85, 0)
	self.Muzzle = part("Muzzle", Vector3.new(0.1, 0.1, 0.1), muzzleOffset,
		visual.ProjectileColor, weapon, self.ArmParts)
	self.Muzzle.Transparency = 1
	self:SetFacing(Vector3.zero, Vector3.new(0, 0, -1))
	model.Parent = parent
	return self
end

function RangedRig:SetFacing(position, targetPosition)
	local flatTarget = Vector3.new(targetPosition.X, position.Y, targetPosition.Z)
	if (flatTarget - position).Magnitude < 0.001 then return end
	local facing = CFrame.lookAt(position, flatTarget)
	if self.Facing == facing then return end
	self.Facing = facing
	for _, entry in self.StaticParts do
		entry.Part.CFrame = facing * entry.Offset
	end
	self:SetPose(self.Angle)
end

function RangedRig:SetPose(angle)
	self.Angle = angle
	local shoulder = self.Facing * CFrame.new(Vector3.new(1.1, 0.75, 0) * self.Scale)
		* CFrame.Angles(math.rad(angle), 0, 0)
	for _, entry in self.ArmParts do
		entry.Part.CFrame = shoulder * entry.Offset
	end
end

function RangedRig:SetProjectileProgress(targetPosition, progress, target)
	if not self.Projectile then
		local projectile = Instance.new("Part")
		local visual = self.Config.Visual
		projectile.Name = self.Config.CombatStyle == "Bow" and "Arrow" or "MagicBolt"
		projectile.Size = visual.ProjectileSize * self.Scale
		projectile.Color = visual.ProjectileColor
		projectile.Material = self.Config.CombatStyle == "Bow" and Enum.Material.Wood or Enum.Material.Neon
		projectile.Shape = self.Config.CombatStyle == "Bow" and Enum.PartType.Block or Enum.PartType.Ball
		projectile.Anchored = true
		projectile.CanCollide = false
		projectile.CanTouch = false
		projectile.CanQuery = false
		self.ProjectileStart = self.Muzzle.Position
		self.ProjectileEnd = targetPosition
		self.Projectile = projectile
		self.ProjectileTarget = target
		projectile:SetAttribute("OwnerUserId", self.Model:GetAttribute("OwnerUserId"))
		projectile:SetAttribute("ContextId", self.Model:GetAttribute("ContextId"))
		projectile:SetAttribute("HeroId", self.Model:GetAttribute("HeroId"))
		projectile:SetAttribute("TargetEnemyId", target and target.Model:GetAttribute("EnemyId"))
		projectile.Parent = self.Model
	end
	local start = self.ProjectileStart
	local finish = self.ProjectileEnd
	local position = start + (finish - start) * math.clamp(progress, 0, 1)
	-- Keep orientation valid at impact, where position equals the destination.
	self.Projectile.CFrame = CFrame.lookAt(position, position + (finish - start))
end

function RangedRig:ClearProjectile()
	if self.Projectile then
		self.Projectile:Destroy()
		self.Projectile = nil
		self.ProjectileTarget = nil
		self.ProjectileStart, self.ProjectileEnd = nil, nil
	end
end

function RangedRig:Destroy()
	self:ClearProjectile()
	self.Model:Destroy()
end

return RangedRig
