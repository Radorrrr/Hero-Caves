return {
	FolderName = "HeroCavesWorld",
	HubPosition = Vector3.new(0, -2, 0),
	HubSize = Vector3.new(88, 4, 88),
	HubSpawnOffset = Vector3.new(0, 1, 22),
	IslandCount = 6,
	IslandRadius = 150,
	IslandSize = Vector3.new(64, 4, 64),
	StartAngleDegrees = -90,
	-- nil uses 360 / IslandCount; override for other prototype layouts.
	AngularSpacingDegrees = nil,
	BridgeWidth = 12,
	BridgeThickness = 2,
	-- Keep embedded bridge ends below floor surfaces, avoiding coplanar top faces.
	BridgeSurfaceDrop = 0.2,
	ClaimZoneSize = Vector3.new(20, 8, 12),
	ClaimZoneOffset = Vector3.new(0, 4, -22),
	PlayerSpawnOffset = Vector3.new(0, 1, -8),
	CaveOffset = Vector3.new(0, 0, 16),
	EnemyOffset = Vector3.new(0, 4, 5),
	-- Additional named hero slots need only another entry here.
	HeroSlots = {
		KnightSlot = Vector3.new(0, 2.4, -0.3),
		ArcherSlot = Vector3.new(5, 2.4, -4),
		MageSlot = Vector3.new(-5, 2.4, -4),
	},
	ClaimFeedbackCooldown = 1,
}
