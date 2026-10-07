local Services = script.Parent.Services
require(Services.EconomyService).Start()
require(Services.ProgressionService).Start()
-- Subscribe to claim/release before IslandService enables claim touch handlers.
require(Services.CombatContextService).Start()
require(Services.CombatDebugService).Start()
-- Shop subscribes before Hub generation publishes its prompt.
require(Services.HeroShopService).Start()
require(Services.IslandService).Start()
