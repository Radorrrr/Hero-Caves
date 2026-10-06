# Hero Caves

Server-side Roblox/Rojo prototype: one stationary enemy per wave, replicated
health display, exponential health scaling, timed bosses and one automatic
Knight with a procedural sword attack, personal gold and purchasable Knight
levels and hero-specific milestone upgrades. No shop, persistence or client damage system is implemented.

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
  time limit, debug logging, gold cap, purchase cooldown and disabled-by-default
  Studio-only testing values.
- `src/shared/EnemyConfig.lua`: names, temporary appearance, base HP, growth
  and boss multiplier.
- `src/shared/HeroConfig.lua`: Knight base damage, damage/level-cost growth,
  level cap, milestones, attack interval, slot offset, appearance, animation
  timings/angles and hit flash. Each future hero defines its own stats/milestones.
- `src/server/Services`: enemy ownership, wave transitions, authoritative
  combat and hero lifecycle.
- `src/server/Heroes/KnightRig.lua`: replaceable procedural Knight visual.
- `src/server/ProgressionMath.lua`: centralized server reward, damage and cost calculations.
- `src/server/UpgradeEffects.lua`: generic purchased-effect calculation.
- `src/server/Services/EconomyService.lua`: personal gold balances and death rewards.
- `src/server/Services/ProgressionService.lua`: per-player/per-hero levels,
  purchased upgrades, replicated stats, validated purchases and shared hero ownership.
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
from the owner's server-calculated level and purchased effects, and rejects stale targets. Nonlethal hits briefly
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

Base formulas remain unchanged:

- Normal reward: `5 * 1.15^(Wave - 1)`.
- Boss reward: `5 * 1.15^(Wave - 1) * 5`. Wave 5 awards 44 gold.
- Knight base level damage: `20 * 1.08^(Level - 1)`.
- Next level cost: `10 * 1.12^(CurrentLevel - 1)`.

The first kills award 5 and 6 gold. Buying Level 2 costs 10 gold, leaving 1;
damage rises from 20 to 22 and the next cost is 11. Combat reads the owner's
current server-calculated damage at the sword impact. It remains synchronized
with the existing animation.

The client fires `HeroCavesRemotes.BuyHeroLevel(heroId)`.
The server rejects extra arguments, validates the hero ID and rate-limits all
purchase requests together per player to one every 0.25s. It
calculates the real cost, checks its private ledger, deducts gold and increments
the private level in a transaction that does not yield. Player attributes are
display data; changing them cannot change the server's gold or level.
The same remote reports success or failure for UI feedback.

Rewards come only from EnemyService's death signal. Each defeated enemy is
marked as rewarded once. Replacing an enemy or timing out a boss awards nothing.
The prototype caps gold/numeric progression results at 1 trillion and Knight
levels at 200. These limits are configurable and avoid unbounded number handling.

### Progression tests in Studio

1. Pull, sync and restart Play. Check GOLD 0, Level 1, Damage 20 and a gray
   Level Up button costing 10 Gold.
2. Let Waves 1 and 2 die. Gold should be 5, then 11; the button becomes green.
3. Click once: Gold 1, Level 2, Damage 22, next cost 11. Clicking while
   unaffordable must not change gold or level. Watch the next sword hit deal 22.
4. Defeat Boss 5: gold rises by 44 exactly once. Repeat the low-BaseDamage
   timeout check above without buying levels: boss removal must award no gold.
5. From a **client** Command Bar, try
   `game.ReplicatedStorage.HeroCavesRemotes.BuyHeroLevel:FireServer("Knight", 0, 999)`.
   Gold and level must not change. Repeated ID-only requests remain subject
   to server affordability checks and throttling.
6. Use Studio's two-player local server test. Each player gets their own reward,
   starts at Level 1 and spends only their own gold. A purchase on the second
   client must not alter the first client's gold/level. When the combat owner
   leaves, the remaining player's purchased level takes over.

## Hero-specific milestone upgrades

Upgrades belong to a player and a hero, identified by `(heroId, upgradeId)`.
The same ID can safely exist on different heroes; it must be unique and stable
within its hero's config. New heroes can define completely different milestone
tables without editing the purchase/effect system.

| Level | Upgrade | Effect | Gold cost |
| --- | --- | --- | --- |
| 10 | Sharpened Blade | This hero damage x2 | 100 |
| 25 | Knight Training | This hero damage x2 | 1,000 |
| 50 | Treasure Hunter | Personal gold earned x1.25 | 10,000 |
| 100 | Sword Mastery | This hero damage x5 | 1,000,000 |
| 150 | Battle Inspiration | All your heroes damage x1.25 | 100,000,000 |
| 200 | Legendary Knight | This hero damage x10 | 10,000,000,000 |

Below the required level an upgrade is **Locked**. At the level it becomes
**Available**, with no effect yet. A successful gold purchase makes it
**Purchased** for the remainder of the session. The HUD lists all milestones
in a scrollable section with names, requirements, descriptions, costs and states.
An available but unaffordable purchase stays visibly unavailable to click.

`BuyUpgrade(heroId, upgradeId)` sends only two IDs. The server validates the
player, hero, upgrade, required level, purchased state and affordability. Extra
arguments, unknown/malformed IDs and repeated purchases are rejected.
Gold deduction and purchased-state changes never yield. Config values and
private server state are authoritative; replicated folders are display data.

Effective values are recalculated from base stats, level and the set of purchased
IDs. Purchasing never mutates BaseDamage or multiplies an already-multiplied
damage value. Supported effect scopes are:

- `HeroDamageMultiplier`: the hero whose upgrade was purchased.
- `GlobalHeroDamageMultiplier`: all heroes belonging to that player.
- `SpecificHeroDamageMultiplier`: the configured `TargetHeroId`, including
  a different hero from the upgrade's owner.
- `BossDamageMultiplier`: the owning hero, only against an enemy flagged boss.
- `AttackSpeedMultiplier`: the owning hero's attack speed.
- `GoldMultiplier`: all enemy gold earned by that player.

Damage uses unrounded base level damage multiplied by local, global and
target-specific layers, plus the boss layer when applicable, then rounds once.
Gold first uses the enemy's existing rounded base reward, multiplies by that
recipient's purchased gold bonuses, then rounds again. Multiple gold bonuses
multiply together; starting gold and raw `AddGold` grants are not multiplied.
For example a 100-gold reward becomes 125 with Treasure Hunter.

Attack interval is `BaseAttackInterval / AttackSpeedMultiplier`. The procedural
animation timeline is accelerated by the same factor, preserving the sword
impact. Attack Speed x1.25 gives a 1.04s interval from the base 1.3s and a
0.352s impact from the base 0.44s. Current Knight milestones do not grant speed,
boss or targeted damage; those effect types are ready for future definitions.
In-flight attacks keep their animation speed until they finish.

### Fast milestone tests in Studio

In `GameConfig.StudioTesting`, set:

```lua
Enabled = true,
StartingGold = 1000000000000,
StartingHeroLevels = {Knight = 10},
```

Stop Play, sync, and start Play for each desired starting level:
**10, 25, 50, 100, 150 or 200**. All upgrades still start unpurchased.
At Level 10, check damage 40 and Sharpened Blade AVAILABLE; buy it for 100 gold
and verify damage 80 and PURCHASED. Clicking again must not charge or stack.
Use Level 9 for the corresponding LOCKED check.

At each other milestone, buy the relevant upgrade and compare damage or gold
before/after. Damage is rounded once after modifiers, so displayed integer
damage ratios can differ slightly from the nominal multiplier. Treasure Hunter
should show `Gold earned x1.25` and change a Boss 5 reward from 44 to 55.
Early enemies die immediately at high levels; inspect the replicated damage
stats alongside combat Output. High-level damage upgrades can be bought in
any order once unlocked; earlier upgrades are not prerequisites.

For two-player testing, verify upgrade purchases/states remain personal and the
active shared hero changes stats when its owner leaves. A non-owner's gold bonus
still affects that player's own rewards immediately.

These shortcuts are gated on the server by `RunService:IsStudio()` and the
Enabled flag. They are ignored in production even when the flag is left on.
There is no test remote or client-settable level/gold command. Set Enabled back
to false after testing. Normal defaults remain 0 gold, Level 1, no upgrades.

There is no saving: leaving/rejoining resets personal gold, levels and upgrades.

The current wave is exposed as the Workspace attribute `HeroCavesWave`.
Enemy models in `Workspace.HeroCavesEnemies` expose `Wave`, `IsBoss`,
`Health`, `MaxHealth`, `GoldReward` and, for bosses, `TimeRemaining` attributes.
The Knight exposes `HeroId`, `AttackPhase`, `OwnerUserId`, `Level` and
`Damage` attributes. Player attributes expose `Gold`, `KnightLevel`,
`KnightDamage`, `KnightNextLevelCost`, `KnightAtMaxLevel` and
`GoldMultiplier` and `IsHeroCombatOwner`. Generic hero snapshots live under
`Player.HeroProgression.<HeroId>` with `Level`, `Damage`, `BossDamage`,
`NextLevelCost`, `AtMaxLevel` and `AttackInterval` attributes. Its
`Upgrades` child has each upgrade ID as an attribute holding its state.
The Workspace owner attribute is `HeroCombatOwnerUserId`. These are replicated
display/debug data; gameplay remains on the server.

This foundation has one shared encounter and one Knight per server. Every present
player receives the full kill reward, adjusted by their own gold bonuses, into
their personal balance. The first player
selected on join/startup owns the shared Knight's combat stats until they leave;
then another present player takes over. Other players can buy personal Knight
levels and upgrades, but their damage/speed effects affect the visible Knight
only when they become its owner. Global/cross-hero effects apply within a player's
own progression, not to other players. The HUD identifies whose combat stats
are active. Future heroes require config plus model/combat behavior and a rig
factory; the generic progression/effect system needs no hero-specific branches.
The current UI displays the configured starting hero. There are no
independent bases, personal enemies or extra hero models yet. The Knight is idle
when no player is present. Roblox Studio is
required to verify actual rendering and gameplay; standalone Luau checks
cannot replace Studio. The temporary rig is built from anchored Parts with
a procedural shoulder pivot, not a Humanoid or uploaded animation. It has no
walking, IK or physics-based sword collision; damage is timed and targeted.
Server-replicated poses and HP may appear slightly offset under network lag.
Slot spacing, visual scale and swing angles need tuning together if changed.
