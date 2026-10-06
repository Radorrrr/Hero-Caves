return {
	Knight = {
		Name = "Knight",
		Damage = 20,
		-- Minimum time between attack starts, including animation and cooldown.
		AttackInterval = 1.3,
		SlotOffset = Vector3.new(0, -1.6, 5.3),
		Animation = {
			WindupDuration = 0.28,
			SwingDuration = 0.16,
			FollowThroughDuration = 0.14,
			RecoveryDuration = 0.32,
			IdleAngle = 65,
			WindupAngle = 165,
			ImpactAngle = 100,
			FollowThroughAngle = 65,
		},
		Visual = {
			ArmorColor = Color3.fromRGB(150, 165, 185),
			DarkArmorColor = Color3.fromRGB(65, 75, 95),
			ClothColor = Color3.fromRGB(150, 35, 45),
			BladeColor = Color3.fromRGB(220, 235, 245),
			GoldColor = Color3.fromRGB(205, 165, 65),
			GripColor = Color3.fromRGB(75, 45, 30),
			Scale = 1,
		},
	},
	Impact = {
		FlashColor = Color3.fromRGB(255, 245, 200),
		FlashDuration = 0.12,
	},
}
