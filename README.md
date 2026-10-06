# Hero Caves

Server-side Roblox/Rojo prototype: one stationary enemy per wave, replicated
health display, exponential health scaling, timed bosses and one automatic
Knight with a procedural sword attack, personal gold and purchasable Knight
levels. No shop, milestone upgrades, persistence or client damage system is implemented.

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
  time limit, debug logging, gold cap and purchase cooldown.
- `src/shared/EnemyConfig.lua`: names, temporary appearance, base HP, growth
  and boss multiplier.
- `src/shared/HeroConfig.lua`: Knight base damage, damage/level-cost growth,
  level cap, attack interval, slot offset, appearance, animation timings/angles
  and hit flash.
- `src/server/Services`: enemy ownership, wave transitions, authoritative
  combat and hero lifecycle.
- `src/server/Heroes/KnightRig.lua`: replaceable procedural Knight visual.
- `src/server/ProgressionMath.lua`: centralized server reward, damage and cost calculations.
- `src/server/Services/EconomyService.lua`: personal gold balances and death rewards.
- `src/server/Services/ProgressionService.lua`: personal levels, purchases,
  replicated stats and shared Knight ownership.
- `src/shared/NumberFormatter.lua`: UI number display only; no gameplay formulas.

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
from the owner's server-calculated level and rejects stale targets. Nonlethal hits briefly
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
5. To test timeout, stop Play, change `HeroConfig.Knight.BaseDamage` to 5, sync and
   restart Play. Wave 5 should time out, remove the boss and return to Wave 4.
   Restore BaseDamage to 20 afterwards.
6. Stop the hero through the **server** Command Bar if needed:
   `require(game.ServerScriptService.Server.Services.HeroService).Stop()`.
   No further damage should occur. Calling `Start()` twice should create only
   one Knight and one hero update connection.

Restart Play after source/config changes because required modules are cached.

## Gold and Knight leveling

Each player joins with 0 gold and Knight Level 1. The prototype HUD displays
personal gold, level, damage and the next level cost. The button turns green
when affordable and gray otherwise. Values update on replicated attribute
changes, not a per-frame UI loop.

All results are rounded to the nearest integer, after applying multipliers:

- Normal reward: `5 * 1.15^(Wave - 1)`.
- Boss reward: `5 * 1.15^(Wave - 1) * 5`. Wave 5 awards 44 gold.
- Knight damage: `20 * 1.08^(Level - 1)`.
- Next level cost: `10 * 1.12^(CurrentLevel - 1)`.

The first kills award 5 and 6 gold. Buying Level 2 costs 10 gold, leaving 1;
damage rises from 20 to 22 and the next cost is 11. Combat reads the owner's
current server-calculated damage at the sword impact. It remains synchronized
with the existing animation.

The client fires `HeroCavesRemotes.BuyKnightLevel` without arguments.
The server rejects payloads, rate-limits requests per player to one every 0.25s,
calculates the real cost, checks its private ledger, deducts gold and increments
the private level in a transaction that does not yield. Player attributes are
display data; changing them cannot change the server's gold or level.
The same remote reports success or failure for UI feedback.

Rewards come only from EnemyService's death signal. Each defeated enemy is
marked as rewarded once. Replacing an enemy or timing out a boss awards nothing.
The prototype caps gold/numeric progression results at 1 trillion and Knight
levels at 200. These limits are configurable and avoid unbounded number handling.
No milestone effects are implemented; damage calculation has a single server
function where later modifiers can be incorporated.

### Progression tests in Studio

1. Pull, sync and restart Play. Check GOLD 0, Level 1, Damage 20 and a gray
   Level Up button costing 10 Gold.
2. Let Waves 1 and 2 die. Gold should be 5, then 11; the button becomes green.
3. Click once: Gold 1, Level 2, Damage 22, next cost 11. Clicking while
   unaffordable must not change gold or level. Watch the next sword hit deal 22.
4. Defeat Boss 5: gold rises by 44 exactly once. Repeat the low-BaseDamage
   timeout check above without buying levels: boss removal must award no gold.
5. From a **client** Command Bar, try
   `game.ReplicatedStorage.HeroCavesRemotes.BuyKnightLevel:FireServer(0, 999, 99999)`.
   Gold and level must not change. Repeated payload-free requests remain subject
   to server affordability checks and throttling.
6. Use Studio's two-player local server test. Each player gets their own reward,
   starts at Level 1 and spends only their own gold. A purchase on the second
   client must not alter the first client's gold/level. When the combat owner
   leaves, the remaining player's purchased level takes over.

There is no saving: leaving/rejoining resets personal gold and levels.

The current wave is exposed as the Workspace attribute `HeroCavesWave`.
Enemy models in `Workspace.HeroCavesEnemies` expose `Wave`, `IsBoss`,
`Health`, `MaxHealth`, `GoldReward` and, for bosses, `TimeRemaining` attributes.
The Knight exposes `HeroId`, `AttackPhase`, `OwnerUserId`, `Level` and
`Damage` attributes. Player attributes expose `Gold`, `KnightLevel`,
`KnightDamage`, `KnightNextLevelCost`, `KnightAtMaxLevel` and
`IsKnightCombatOwner`. These are replicated
display/debug data; gameplay remains on the server.

This foundation has one shared encounter and one Knight per server. Every present
player receives the full kill reward into their personal balance. The first player
selected on join/startup owns the shared Knight's combat stats until they leave;
then another present player takes over. Other players can buy personal Knight
levels, but those levels affect the visible Knight only when they become its owner.
The HUD explicitly identifies whether your levels are active. There are no
independent bases, personal enemies or extra hero models yet. The Knight is idle
when no player is present. Roblox Studio is
required to verify actual rendering and gameplay; standalone Luau checks
cannot replace Studio. The temporary rig is built from anchored Parts with
a procedural shoulder pivot, not a Humanoid or uploaded animation. It has no
walking, IK or physics-based sword collision; damage is timed and targeted.
Server-replicated poses and HP may appear slightly offset under network lag.
Slot spacing, visual scale and swing angles need tuning together if changed.
