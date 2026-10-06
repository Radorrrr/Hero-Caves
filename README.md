# Hero Caves

First server-side Roblox/Rojo foundation: one stationary enemy per wave,
replicated health display, exponential health scaling and timed bosses.
No hero, currency, persistence or client damage system is implemented.

## Rojo and Studio

Use the existing `default.project.json` with Rojo 7.7.1:

```sh
rojo serve default.project.json
```

Connect the Rojo Studio plugin to the server and sync into a test place, then
press **Play**. In a blank place, add a Baseplate and SpawnLocation in Studio
for the player to stand on. The server creates the anchored enemy at
`Vector3.new(0, 4, -15)`; no model or place files are needed in this repository.
View the enemy's BillboardGui and server Output while testing.

## Configuration and testing

- `src/shared/GameConfig.lua`: spawn position, wave delay, boss interval and
  time limit, temporary attack settings and debug logging.
- `src/shared/EnemyConfig.lua`: names, temporary appearance, base HP, growth
  and boss multiplier.
- `src/server/Services`: enemy ownership, wave transitions and the removable
  temporary server attacker.

Wave 1 starts automatically. With defaults, Waves 1–4 have 20, 24, 28 and
33 HP. The attacker deals 5 damage each second; defeated enemies disappear
and the next wave starts after about one second. Wave 5 is a purple Boss
Slime with 330 HP, a boss label and a visible 30-second countdown.
The default attacker cannot defeat it in time: the boss disappears and Wave 4
returns, then the boss can be attempted again.

To test boss victory, set `TestDamage = 20`, sync, and restart Play. Defeating
the first boss before its deadline advances to Wave 6. Restart Play after
configuration changes because required modules are cached during a session.
Disable `TestAttackerEnabled` when replacing the temporary attacker with a
future HeroService; `CombatService.Stop()` also disconnects it at runtime.

The current wave is exposed as the Workspace attribute `HeroCavesWave`.
Enemy models in `Workspace.HeroCavesEnemies` expose `Wave`, `IsBoss`,
`Health`, `MaxHealth` and, for bosses, `TimeRemaining` attributes.
These are replicated display/debug data; gameplay remains on the server.

This foundation has one shared encounter per server, including multiplayer.
It does not yet provide independent player progression. Roblox Studio is
required to verify actual rendering and gameplay; standalone Luau checks
cannot replace Studio.
