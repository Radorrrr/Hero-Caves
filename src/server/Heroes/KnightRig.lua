local KnightRig = {}
KnightRig.__index = KnightRig

function KnightRig.new(config, parent)
	local self = setmetatable({}, KnightRig)
	local visual = config.Visual
	self.Scale = visual.Scale
	self.StaticParts = {}
	self.ArmParts = {}
	self.Angle = config.Animation.IdleAngle

	local model = Instance.new("Model")
	model.Name = config.Name
	model:SetAttribute("HeroId", "Knight")
	self.Model = model
	local body = Instance.new("Folder")
	body.Name = "Body"
	body.Parent = model
	local arm = Instance.new("Folder")
	arm.Name = "SwordArm"
	arm.Parent = model
	local sword = Instance.new("Folder")
	sword.Name = "Sword"
	sword.Parent = arm

	local function part(name, size, offset, color, container, list)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * self.Scale
		p.Color = color
		p.Material = Enum.Material.Metal
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Parent = container
		table.insert(list, {Part = p, Offset = CFrame.new(offset * self.Scale)})
		return p
	end

	local function armor(name, size, offset, color)
		return part(name, size, offset, color or visual.ArmorColor, body, self.StaticParts)
	end

	local root = armor("Root", Vector3.new(0.2, 0.2, 0.2), Vector3.zero)
	root.Transparency = 1
	model.PrimaryPart = root
	armor("Torso", Vector3.new(1.8, 1.9, 0.9), Vector3.zero)
	armor("Tabard", Vector3.new(0.8, 1.6, 0.1), Vector3.new(0, -0.1, -0.51), visual.ClothColor)
	armor("Belt", Vector3.new(1.9, 0.2, 1), Vector3.new(0, -0.65, 0), visual.GripColor)
	armor("Head", Vector3.new(1.15, 1.05, 1.05), Vector3.new(0, 1.65, 0))
	armor("HelmetCrest", Vector3.new(0.2, 0.35, 0.85), Vector3.new(0, 2.3, 0), visual.ClothColor)
	armor("Visor", Vector3.new(0.95, 0.16, 0.12), Vector3.new(0, 1.7, -0.58), visual.DarkArmorColor)
	armor("NoseGuard", Vector3.new(0.14, 0.55, 0.13), Vector3.new(0, 1.55, -0.65))
	armor("LeftShoulder", Vector3.new(0.8, 0.55, 1.05), Vector3.new(-1.25, 0.75, 0))
	armor("RightShoulder", Vector3.new(0.8, 0.55, 1.05), Vector3.new(1.25, 0.75, 0))
	armor("LeftArm", Vector3.new(0.6, 1.7, 0.7), Vector3.new(-1.25, -0.25, 0))
	armor("LeftGlove", Vector3.new(0.65, 0.4, 0.75), Vector3.new(-1.25, -1.1, 0), visual.DarkArmorColor)
	for _, side in {-1, 1} do
		local prefix = side == -1 and "Left" or "Right"
		armor(prefix .. "Leg", Vector3.new(0.7, 1.25, 0.75), Vector3.new(side * 0.48, -1.45, 0))
		armor(prefix .. "Boot", Vector3.new(0.8, 0.6, 1.2), Vector3.new(side * 0.48, -2.1, -0.2), visual.DarkArmorColor)
	end

	-- Arm and sword share a shoulder pivot; no uploaded rig/animation is required.
	part("RightArm", Vector3.new(0.6, 1.7, 0.7), Vector3.new(0, -0.85, 0), visual.ArmorColor, arm, self.ArmParts)
	part("RightGlove", Vector3.new(0.65, 0.4, 0.75), Vector3.new(0, -1.7, 0), visual.DarkArmorColor, arm, self.ArmParts)
	part("Grip", Vector3.new(0.22, 0.65, 0.22), Vector3.new(0, -1.75, 0), visual.GripColor, sword, self.ArmParts)
	part("Pommel", Vector3.new(0.32, 0.2, 0.32), Vector3.new(0, -1.35, 0), visual.GoldColor, sword, self.ArmParts)
	part("Crossguard", Vector3.new(1.1, 0.18, 0.3), Vector3.new(0, -2.1, 0), visual.GoldColor, sword, self.ArmParts)
	part("Blade", Vector3.new(0.34, 2.5, 0.15), Vector3.new(0, -3.4, 0), visual.BladeColor, sword, self.ArmParts)

	self:SetFacing(Vector3.zero, Vector3.new(0, 0, -1))
	model.Parent = parent
	return self
end

function KnightRig:SetFacing(position, targetPosition)
	local flatTarget = Vector3.new(targetPosition.X, position.Y, targetPosition.Z)
	if (flatTarget - position).Magnitude < 0.001 then
		return
	end
	local facing = CFrame.lookAt(position, flatTarget)
	if self.Facing == facing then
		return
	end
	self.Facing = facing
	for _, entry in self.StaticParts do
		entry.Part.CFrame = facing * entry.Offset
	end
	self:SetPose(self.Angle)
end

function KnightRig:SetPose(angle)
	self.Angle = angle
	local shoulder = self.Facing * CFrame.new(Vector3.new(1.25, 0.75, 0) * self.Scale)
		* CFrame.Angles(math.rad(angle), 0, 0)
	for _, entry in self.ArmParts do
		entry.Part.CFrame = shoulder * entry.Offset
	end
end

function KnightRig:Destroy()
	self.Model:Destroy()
end

return KnightRig
