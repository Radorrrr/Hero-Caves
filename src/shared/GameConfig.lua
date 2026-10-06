return {
	EnemySpawnPosition = Vector3.new(0, 4, -15),
	WaveDelay = 1,
	BossEveryWaves = 5,
	BossTimeLimit = 30,
	DebugLogging = true,
	Economy = {
		MaxGold = 1000000000000,
		PurchaseCooldown = 0.25,
	},
	-- Ignored outside Studio, even if accidentally left enabled.
	StudioTesting = {
		Enabled = false,
		StartingGold = 1000000000000,
		StartingHeroLevels = {Knight = 1, Archer = 1, Mage = 1},
		StartingOwnedHeroes = {Archer = false, Mage = false},
	},
}
