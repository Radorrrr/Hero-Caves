# Hero Caves

Server-side Roblox/Rojo prototype: one stationary enemy per wave, replicated
health display, exponential health scaling, timed bosses and one automatic
Knight with a procedural sword attack. No shop, upgrades, currency, persistence
or client damage system is implemented.

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

- `src/shared/GameConfig.lua`: spawn position, wave delay, boss interval,
  time limit and debug logging.
- `src/shared/EnemyConfig.lua`: names, temporary appearance, base HP, growth
  and boss multiplier.
- `src/shared/HeroConfig.lua`: Knight damage, attack interval, slot offset,
  appearance, animation timings/angles and hit flash.
- `src/server/Services`: enemy ownership, wave transitions, authoritative
  combat and hero lifecycle.
- `src/server/Heroes/KnightRig.lua`: replaceable procedural Knight visual.

Wave 1 and a single Knight start automatically. With defaults, Waves 1–4
have 20, 24, 28 and 33 HP. The Knight stands at a fixed slot near the enemy,
faces it and deals 20 damage per sword hit. Defeated enemies disappear and
the next wave starts after about one second. During the gap the Knight is idle.
Wave 5 is a purple Boss Slime with 330 HP, a boss label and a visible
30-second countdown. The default Knight can defeat it and reach Wave 6.

The sword uses sine-eased shoulder poses: 0.28s wind-up, 0.16s swing, impact
at 0.44s, 0.14s follow-through and 0.32s recovery. Attack starts are at least
1.3s apart. The same server update sets the impact pose and calls
`CombatService.DamageEnemy(hero, capturedEnemy)` once. Combat reads damage
from the server's HeroConfig and rejects stale targets. Nonlethal hits briefly
flash the enemy. The old automatic test attacker and its settings are removed.

### Studio checks

1. Pull the latest GitHub changes, run Rojo, sync all source and start Play.
   Use a floor with its top at Y=0, or adjust `Knight.SlotOffset.Y` to your floor.
2. Find exactly one Knight in `Workspace.HeroCavesHeroes`. Check head, helmet,
   torso, arms, legs and sword. It should face the slime without walking.
3. Watch a swing on Wave 2: HP stays unchanged during anticipation, then drops
   from 24 to 4 at impact with a short flash. The arm recovers before attacking
   again. The Knight should remain idle between enemies and target the next one.
4. Let the defaults reach Wave 5. Observe the boss timer and 20-HP hits; a
   victory must advance to Wave 6 before the 30-second deadline.
5. To test timeout, stop Play, change `HeroConfig.Knight.Damage` to 5, sync and
   restart Play. Wave 5 should time out, remove the boss and return to Wave 4.
   Restore Damage to 20 afterwards.
6. Stop the hero through the **server** Command Bar if needed:
   `require(game.ServerScriptService.Server.Services.HeroService).Stop()`.
   No further damage should occur. Calling `Start()` twice should create only
   one Knight and one hero update connection.

Restart Play after source/config changes because required modules are cached.

The current wave is exposed as the Workspace attribute `HeroCavesWave`.
Enemy models in `Workspace.HeroCavesEnemies` expose `Wave`, `IsBoss`,
`Health`, `MaxHealth` and, for bosses, `TimeRemaining` attributes.
The Knight exposes `HeroId` and `AttackPhase` attributes. These are replicated
display/debug data; gameplay remains on the server.

This foundation has one shared encounter per server, including multiplayer.
It does not yet provide independent player progression. Roblox Studio is
required to verify actual rendering and gameplay; standalone Luau checks
cannot replace Studio. The temporary rig is built from anchored Parts with
a procedural shoulder pivot, not a Humanoid or uploaded animation. It has no
walking, IK or physics-based sword collision; damage is timed and targeted.
Server-replicated poses and HP may appear slightly offset under network lag.
Slot spacing, visual scale and swing angles need tuning together if changed.
