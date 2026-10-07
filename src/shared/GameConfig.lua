return {
	WaveDelay = 1,
	BossEveryWaves = 5,
	BossTimeLimit = 30,
	DebugLogging = true,
	Persistence = {
		DataStoreName = "IdleHeroSimulator_PlayerData_v1",
		StudioDataStoreName = "IdleHeroSimulator_StudioPlayerData_v1",
		StudioDebugDataStoreName = "IdleHeroSimulator_StudioDebugPlayerData_v1",
		StudioMode = "Memory", -- Explicitly opt into DataStore only in a published test place.
		AutosaveInterval = 90,
		MaxAttempts = 3,
		RetryDelay = 1,
		SessionLeaseSeconds = 300,
		MaxSavedWave = 1000, -- Numeric safety for restored enemy HP/reward calculations.
	},
	Economy = {
		MaxGold = 1000000000000,
		PurchaseCooldown = 0.25,
	},
	-- Ignored outside Studio, even if accidentally left enabled.
	StudioTesting = {
		Enabled = false,
		PlayerWalkSpeed = 32, -- nil/false retains Roblox's normal WalkSpeed.
		StartingGold = 1000000000000,
		StartingHeroLevels = {Knight = 1, Archer = 1, Mage = 1},
		StartingOwnedHeroes = {Archer = false, Mage = false},
	},
}
