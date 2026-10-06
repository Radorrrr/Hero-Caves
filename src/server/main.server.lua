local Services = script.Parent.Services
local WaveService = require(Services.WaveService)
local HeroService = require(Services.HeroService)
local EconomyService = require(Services.EconomyService)
local ProgressionService = require(Services.ProgressionService)

EconomyService.Start()
ProgressionService.Start()
WaveService.Start()
HeroService.Start()
require(Services.CombatDebugService).Start()
