return {
	StartingHeroId = "Knight",
	Knight = {
		Name = "Knight",
		BaseDamage = 20,
		DamageGrowth = 1.08,
		BaseLevelCost = 10,
		LevelCostGrowth = 1.12,
		MaxLevel = 200,
		Milestones = {
			{
				Id = "SharpenedBlade", Level = 10, Name = "Sharpened Blade",
				Description = "This hero's damage x2", Cost = 100,
				Effect = {Type = "HeroDamageMultiplier", Value = 2},
			},
			{
				Id = "KnightTraining", Level = 25, Name = "Knight Training",
				Description = "This hero's damage x2", Cost = 1000,
				Effect = {Type = "HeroDamageMultiplier", Value = 2},
			},
			{
				Id = "TreasureHunter", Level = 50, Name = "Treasure Hunter",
				Description = "Your gold earned x1.25", Cost = 10000,
				Effect = {Type = "GoldMultiplier", Value = 1.25},
			},
			{
				Id = "SwordMastery", Level = 100, Name = "Sword Mastery",
				Description = "This hero's damage x5", Cost = 1000000,
				Effect = {Type = "HeroDamageMultiplier", Value = 5},
			},
			{
				Id = "BattleInspiration", Level = 150, Name = "Battle Inspiration",
				Description = "All your heroes' damage x1.25", Cost = 100000000,
				Effect = {Type = "GlobalHeroDamageMultiplier", Value = 1.25},
			},
			{
				Id = "LegendaryKnight", Level = 200, Name = "Legendary Knight",
				Description = "This hero's damage x10", Cost = 10000000000,
				Effect = {Type = "HeroDamageMultiplier", Value = 10},
			},
		},
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
