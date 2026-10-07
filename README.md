# Hero Caves

Server-side Roblox/Rojo prototype: one stationary enemy per wave, replicated
health display, exponential health scaling, timed bosses, Knight/Archer/Mage,
a hero shop, personal gold, hero levels and hero-specific milestone upgrades,
plus a temporary central Hub and six claimable player islands.
No persistence, final models or client damage system is implemented.

## Rojo and Studio

Use the existing `default.project.json` with Rojo 7.7.1:

```sh
rojo serve default.project.json
```

Connect the Rojo Studio plugin to the server and sync into a test place, then
press **Play**. Phase 6A now generates its own Hub, six islands, bridges and spawn pads.
A separate Baseplate/SpawnLocation is no longer required. The server creates the anchored enemy at
`Vector3.new(0, 4, -15)`; no model or place files are needed in this repository.
View the enemy's BillboardGui and server Output while testing.

## Configuration and testing

- `src/shared/GameConfig.lua`: spawn position, wave delay, boss interval,
  time limit, debug logging, gold cap, purchase cooldown and disabled-by-default
  Studio-only testing values.
- `src/shared/EnemyConfig.lua`: names, temporary appearance, base HP, growth
  and boss multiplier.
- `src/shared/HeroConfig.lua`: all hero stats, unlock prices, default ownership,
  base damage, damage/level-cost growth,
  level cap, milestones, attack interval, slot offset, appearance, animation
  timings/angles and hit flash. Each future hero defines its own stats/milestones.
- `src/server/Services`: enemy ownership, wave transitions, authoritative
  combat and hero lifecycle.
- `src/server/Heroes/KnightRig.lua`: replaceable procedural Knight visual.
- `src/server/Heroes/RangedRig.lua`: prototype Archer/Mage visuals and
  server-interpolated arrow/magic projectiles.
- `src/server/ProgressionMath.lua`: centralized server reward, damage and cost calculations.
- `src/server/UpgradeEffects.lua`: generic purchased-effect calculation.
- `src/server/Services/EconomyService.lua`: personal gold balances and death rewards.
- `src/server/Services/ProgressionService.lua`: per-player/per-hero levels,
  ownership, purchased upgrades, replicated stats, validated purchases and shared combat ownership.
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
   The generated Hub surface is at Y=0, matching the existing shared combat slots.
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

## Hero shop and multi-hero combat

| Hero | Initially owned | Unlock gold | Base hit | Attack interval | Damage growth | Base level cost |
| --- | --- | --- | --- | --- | --- | --- |
| Knight | Yes | 0 | 20 | 1.3s | 1.08 | 10 |
| Archer | No | 100 | 8 | 0.7s | 1.08 | 15 |
| Mage | No | 1,000 | 55 | 2.4s | 1.09 | 40 |

All three use level-cost growth 1.12 and prototype max level 200. Stats, unlock
costs, milestones, rig/combat style and fixed slot offsets live in HeroConfig.
Knight stays in its original front slot; Archer is back-right and Mage back-left.
Their anchored models face the active enemy without chasing or pathfinding.

The HUD lists three hero tabs showing OWNED, AFFORDABLE or NOT AFFORDABLE.
Selecting a tab displays that hero's stats and either BUY HERO or LEVEL UP,
plus only that hero's milestones. Owning/leveling/upgrading one hero never changes
another's ownership, level or purchased IDs. Global/targeted bonuses can change
another owned hero's effective damage as configured.

`HeroCavesRemotes.BuyHero(heroId)` accepts exactly one ID. The server checks
the player, known hero, private ownership, real unlock cost and gold, then spends
and marks ownership without yielding. Duplicate purchases and extra price/stat
arguments are rejected. Hero, level and milestone purchases share the per-player
cooldown. Unowned heroes cannot fight, level up or buy upgrades; their upgrades
do not contribute any effects.

HeroService synchronizes the combat owner's owned roster on the next server
update after purchase. One Heartbeat dispatcher updates separate per-hero
attack starts, cooldowns, impact guards and captured targets. Thus the heroes
attack the same enemy independently, without duplicate loops or a common attack
timer. Owner changes rebuild only the incoming owner's roster and cancel all
outgoing projectiles. A purchase by a non-owner remains personal until they
become the combat owner.

Archer uses a green hood, bow and quiver; Mage uses a robe, hat and glowing staff.
Both are temporary multipart rigs. Their attack anticipation/arm pose is visible.
Archer's 0.12s draw is followed by a 0.22s arrow flight (impact at 0.34s).
Mage's 0.5s cast is followed by a 0.45s bolt flight (impact at 0.95s).
Projectiles are anchored cosmetic Parts interpolated on the server, with no
physics collision or client hit claims. Damage is applied once after the
projectile is placed at the captured enemy's position. Attack-speed upgrades
accelerate the entire timeline. Target death, replacement or boss expiry cancels
pending attacks/projectiles; all heroes wait for the next target.

Health flashes and the visible attacks provide prototype hit feedback. With
DebugLogging enabled, Output names the hero responsible for each impact.
Gold gains now use temporary HUD notifications; no final combat VFX system is included.

### Archer milestones

| Level | Upgrade | Effect | Gold |
| --- | --- | --- | --- |
| 10 | Keen Arrows | Archer damage x2 | 150 |
| 25 | Quick Draw | Archer attack speed x1.25 | 1,500 |
| 50 | Rallying Volley | All your heroes damage x1.20 | 15,000 |
| 100 | Deadeye | Archer damage x5 | 1,500,000 |
| 150 | Giant Slayer | Archer boss damage x2 | 150,000,000 |
| 200 | Legendary Archer | Archer damage x10 | 15,000,000,000 |

### Mage milestones

| Level | Upgrade | Effect | Gold |
| --- | --- | --- | --- |
| 10 | Arcane Focus | Mage damage x2 | 300 |
| 25 | Spellcraft | Mage damage x2 | 3,000 |
| 50 | Enchanted Blade | Knight damage x1.5 | 30,000 |
| 100 | Archmage | Mage damage x5 | 3,000,000 |
| 150 | Alchemical Fortune | Personal gold earned x1.25 | 300,000,000 |
| 200 | Legendary Mage | Mage damage x10 | 30,000,000,000 |

### Fast shop and cross-hero tests in Studio

For buying/activating heroes, set GameConfig.StudioTesting:

```lua
Enabled = true,
StartingGold = 1500,
StartingHeroLevels = {Knight = 1, Archer = 1, Mage = 1},
StartingOwnedHeroes = {Archer = false, Mage = false},
```

Sync and restart Play. Only Knight should exist. Buy Archer for 100, then Mage
for 1,000: the scene should contain exactly three separated heroes, and the
remaining gold reflects those costs plus any kills while shopping. Observe
Boss 5 or later enemies so the target lives long enough to see all three attacks.
Try leveling an unowned hero before buying it; the server must refuse.
Switch tabs and level Archer: Knight/Mage levels must remain unchanged.

For milestone testing, use:

```lua
Enabled = true,
StartingGold = 1000000000000,
StartingHeroLevels = {Knight = 1, Archer = 150, Mage = 150},
StartingOwnedHeroes = {Archer = true, Mage = true},
```

Sync and restart Play. Upgrades are available but unpurchased. Verify:

1. Buy Archer's Rallying Volley: all three effective damages gain x1.20.
2. Buy Mage's Enchanted Blade: only Knight gains another x1.5 (20 -> 24 -> 36).
3. Buy Archer's Quick Draw: its base 0.7s interval becomes 0.56s; impact
   changes from 0.34s to 0.272s. Knight/Mage timing stays unchanged.
4. Buy Archer's Giant Slayer: only Archer gains x2 damage against bosses;
   normal targets receive its unchanged normal damage.
5. Buy Mage's Alchemical Fortune: personal GoldMultiplier becomes 1.25 and
   Boss 5's 44-gold base reward becomes 55 for that player.

High-level attacks kill early enemies immediately. To inspect real hits from
all heroes at those levels, temporarily raise EnemyConfig.BaseHealth to
1,000,000,000 and restart Play; observe per-hero Output damage and model stats.
Stop Play and restore BaseHealth to 20 after the test. Full startgold can also
hit the gold cap: buy upgrades first or spend some gold before checking rewards.
Use Studio's local two-player server to test ownership/purchases remain personal
and leaving transfers the roster to the remaining owner's owned heroes.

All starting gold, levels and ownership overrides require server IsStudio()
and Enabled=true. Starting levels also apply to a hero bought during a Studio
test; production purchases always start at Level 1. There is no gold/level cheat remote.
Restore Enabled=false after testing.

## Gold and Knight leveling

Each player joins with 0 gold and only Knight owned at Level 1. The prototype HUD displays
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

The HUD now fires `HeroCavesRemotes.BuyHeroLevels(heroId, mode)`.
The original `BuyHeroLevel(heroId)` remains supported as x1.
The server rejects extra arguments, validates the hero ID and rate-limits all
purchase requests together per player to one every 0.25s. It
calculates the real cost, checks its private ledger, deducts gold and increments
the private level in a transaction that does not yield. Player attributes are
display data; changing them cannot change the server's gold or level.
The same remote reports success or failure for UI feedback.

Rewards come only from EnemyService's death signal. Each defeated enemy is
marked as rewarded once. Replacing an enemy or timing out a boss awards nothing.
The prototype caps gold/numeric progression results at 1 trillion and Knight
hero levels at 200. These limits are configurable and avoid unbounded number handling.

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
arguments, unknown/malformed IDs, unowned heroes and repeated purchases are rejected.
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
boss or targeted damage; Archer and Mage now use those effect types.
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
should show `Gold Multiplier: x1.25` and change a Boss 5 reward from 44 to 55.
Early enemies die immediately at high levels; inspect the replicated damage
stats alongside combat Output. High-level damage upgrades can be bought in
any order once unlocked; earlier upgrades are not prerequisites.

For two-player testing, verify upgrade purchases/states remain personal and the
active shared hero changes stats when its owner leaves. A non-owner's gold bonus
still affects that player's own rewards immediately.

These shortcuts are gated on the server by `RunService:IsStudio()` and the
Enabled flag. They are ignored in production even when the flag is left on.
There is no client-settable level/gold command; combat controls are Studio-only. Set Enabled back
to false after testing. Normal defaults remain 0 gold, Level 1, no upgrades.

There is no saving: leaving/rejoining resets personal gold, hero ownership,
levels and upgrades.

The current wave is exposed as the Workspace attribute `HeroCavesWave`.
Enemy models in `Workspace.HeroCavesEnemies` expose `Wave`, `IsBoss`,
`Health`, `MaxHealth`, `GoldReward` and, for bosses, `TimeRemaining` attributes.
Each active hero exposes `HeroId`, `AttackPhase`, `OwnerUserId`, `Level` and
`Damage` attributes. Player attributes expose `Gold`, `KnightLevel`,
`KnightDamage`, `KnightNextLevelCost`, `KnightAtMaxLevel` and
`GoldMultiplier` and `IsHeroCombatOwner`. Generic hero snapshots live under
`Player.HeroProgression.<HeroId>` with `Owned`, `UnlockCost`, `Level`, `Damage`, `BossDamage`,
`NextLevelCost`, `AtMaxLevel`, `AttackInterval`, `AttackSpeed`, `DPS` and
`AttackEnabled` attributes. Player `TotalDPS` is the server-calculated normal sum. Its
`Upgrades` child has each upgrade ID as an attribute holding its state.
The Workspace owner attribute is `HeroCombatOwnerUserId`. These are replicated
display/debug data; gameplay remains on the server.

This foundation has one shared encounter per server. Every present
player receives the full kill reward, adjusted by their own gold bonuses, into
their personal balance. The first player
selected on join/startup owns the shared scene's hero roster and combat stats
until they leave; then another present player takes over. Other players can buy
personal heroes, levels and upgrades, but their roster/damage/speed affects the scene
only when they become its owner. Global/cross-hero effects apply within a player's
own progression, not to other players. The HUD identifies whose combat stats
are active. Future heroes require config plus model/combat behavior and a rig
factory; the generic progression/effect system needs no hero-specific branches.
The UI lets the player select each hero. There are no independent bases or
personal enemies yet. No heroes are active when no player is present. Roblox Studio is
required to verify actual rendering and gameplay; standalone Luau checks
cannot replace Studio. The temporary rig is built from anchored Parts with
a procedural shoulder pivot, not a Humanoid or uploaded animation. It has no
walking, IK or physics-based sword collision; damage is timed and targeted.
Server-replicated poses and HP may appear slightly offset under network lag.
Slot spacing, visual scale and swing angles need tuning together if changed.


## Combat information and Studio tools (before Phase 6)

Each owned hero's selected tab shows level, effective normal damage, attack speed
in attacks/second, normal DPS, and the next level's gold cost. The top-right HUD
shows Total DPS. The balance remains visible, separately from **Gold Multiplier**.
The client only formats replicated values; it has no balancing/reward formulas.

The server uses the existing upgraded damage/interval calculations:

- `AttackSpeed = 1 / EffectiveAttackInterval`.
- `DPS = EffectiveNormalDamage / EffectiveAttackInterval`.
- `TotalDPS = sum(DPS)` for the player's owned heroes with attacks enabled.
- Boss-only damage bonuses never enter normal Damage/DPS/Total DPS.
- Gold Multiplier is the product of purchased gold effects on owned heroes.
  It starts at x1; Knight Treasure Hunter and Mage Alchemical Fortune combine
  to x1.5625, displayed as x1.56 (display rounding only).

The normal HUD describes your personal roster. As in Phase 5, only the combat
owner's roster fights in the shared scene; the existing ownership explanation
remains visible. The debug panel instead describes the current scene owner.
DPS is a theoretical attack-rate stat, not a measurement of kills per second;
wave gaps, overkill, initial anticipation and boss timeouts affect actual output.
Per-hero DPS remains visible during debug pause; Total DPS excludes paused heroes.

For a rewarded death, EconomyService applies the player's gold multiplier,
rounds and caps the result, and sends the **actual balance increase** through
`ReplicatedStorage.HeroCavesGoldAwarded`. A client `+… Gold` notification uses
NumberFormatter, waits briefly, then moves/fades and destroys itself. At most
five notifications remain active. Raw grants, starting gold, purchases, enemy
replacement, boss timeout and HP reset do not produce reward notifications.
At the gold cap no positive increase means no notification. For example, Boss 5
awards 44 normally, 55 at x1.25, or 69 at x1.5625, provided there is cap headroom.

### Enable the Studio debug panel

Set `GameConfig.StudioTesting.Enabled = true`, sync all source, and restart Play
in Roblox Studio. Optional testing shortcuts remain available, for example:

```lua
Enabled = true,
StartingGold = 1500,
StartingHeroLevels = {Knight = 1, Archer = 1, Mage = 1},
StartingOwnedHeroes = {Archer = true, Mage = true},
```

The scrollable panel beneath Total DPS provides:

- Pause/Resume ALL attacks; individual Knight/Archer/Mage ON/OFF selections persist
  through a global pause. Controls affect the shared scene for all Studio clients.
- Reset current enemy HP to MaxHealth. Wave, ownership, levels, upgrades, rewards
  and the boss deadline are unchanged. An absent/dead/expired enemy is not revived.
- The scene owner's hero levels, normal damage, interval, attacks/second, DPS and
  effective enabled status, plus wave, HP/max HP, boss flag, gold multiplier and total.

Switching attacks off immediately cancels windups and active projectiles. A
second guard in CombatService rejects disabled impacts. Models remain visible;
resuming starts a fresh attack under the existing cooldown with the same single
HeroService dispatcher. Turning an unowned hero ON does not grant ownership.
Debug settings are shared only for the current server session and do not save.

Both server controls/snapshots and the client panel require **IsStudio AND
Enabled**. Production creates neither debug folder nor control remote. The
server rechecks this gate on each request, accepts only exact action/ID/boolean
payloads, and rate-limits controls to one per player every 0.15s. Restore
Enabled=false after testing. No remote can set damage, levels, gold or upgrades.

Stat snapshots update on purchases, progression/owner changes and debug controls.
Debug enemy snapshots update on spawn, removal, damage or reset. Reward events
occur on awards; these additions do not send stat remotes every frame.

### Verification and manual Studio checks

Standalone Luau simulations using real application modules and mocked Roblox
APIs passed 21 scenarios: existing combat/waves/bosses/shop/security/multiplayer,
new server-derived DPS and totals, all relevant upgrades, boss exclusion,
combined gold rewards, gold cap, notification formatting/cleanup, immediate
projectile cancellation, disabled damage guards, repeated pause/resume,
normal/boss HP reset and Studio/production gating. All Luau source compiles;
Rojo sourcemap/require paths are validated. These checks do not replace Studio
rendering, real TweenService timing or replication tests.

In Studio, verify each owned tab's stats, buy Quick Draw (0.70 -> 0.56s;
1.43 -> 1.79 attacks/s), damage/global/cross upgrades and both gold upgrades.
Compare Total DPS to the unrounded replicated DPS sum (separately rounded HUD
numbers can differ slightly). Observe normal/boss reward popups with gold cap
headroom. Toggle Archer while an arrow is in flight, pause all, reset damaged
normal/boss HP, then resume repeatedly: no canceled hit, duplicate attack loop,
extra reward or wave change should result. With Enabled=false there should be
no debug panel or remote. Test two clients: debug stats follow the combat owner
and personal HUD/rewards remain personal after ownership handoff.

New source modules: `src/client/GoldPopup.lua`,
`src/client/CombatDebugPanel.lua`, `src/server/Services/CombatDebugState.lua`,
and `src/server/Services/CombatDebugService.lua`.
Phase 6, persistence, extra heroes and final art remain outside this change.


## Bulk leveling and per-hero Studio reset (before Phase 6)

The compact **BUY MODE** button cycles x1 -> x10 -> x25 -> x100 -> MAX -> NEXT
-> x1. Selecting a mode is client UI state. The adjacent purchase button and
preview show the currently affordable level count and its exact gold cost;
NEXT also shows the target milestone. Success feedback reports the actual
server-purchased count/cost. Selecting an unowned hero still offers BUY HERO.

`ProgressionMath.GetHeroLevelCost` remains the only per-level cost formula.
`GetBulkLevelCost` sums each individual rounded cost, bounded by the hero's
configured MaxLevel. `GetLevelPurchaseQuote` walks the requested consecutive
levels and stops before the next price exceeds remaining gold. Thus x25 can
buy 17 levels rather than reject the purchase; MAX walks up to MaxLevel and
buys the exact affordable prefix. The server spends the combined cost once,
increments level once and refreshes stats/milestone availability once. No
upgrade is bought automatically, and no per-level remote events are fired.

`GetNextMilestoneTarget` chooses the smallest configured milestone Level strictly
above the current level, regardless of milestone order. NEXT buys toward that
level, partially if needed, then uses that same target on another purchase until
reached. For the current configs, Level 10 targets 25; 17 targets 25; 25 targets
50; 72 targets 100; 149 targets 150. **After the highest configured milestone,
NEXT uses x1**. All modes respect the existing intentional MaxLevel=200; the
logic reads that config rather than treating the highest milestone as a level cap.

Each `Player.HeroProgression.<HeroId>.PurchaseModes.<Mode>` folder replicates
server-calculated `Count`, `Cost`, `Requested` and `Target` quotes. They refresh
on balance/progression changes, not per frame. The client only formats these
quotes; it sends exactly a hero ID and one supported mode string. The server
recalculates from private level, ownership and gold at request time, so a stale
quote cannot select a price/final level. Invalid types, extra arguments, unknown
heroes/modes, unowned heroes, zero affordable levels and MaxLevel are rejected.
Bulk/legacy single-level/shop/upgrade requests share the existing 0.25s cooldown.

The Studio debug panel now has **RESET HERO** under each hero. It resets the
hero belonging to the displayed shared-scene owner to Level 1, clears only that
hero's purchased upgrades, and preserves its owned/unowned status. In particular,
owned Archer/Mage remain owned. Gold, wave, enemy HP/deadline and other hero
levels/upgrades are unchanged. Effects originating from the reset hero are
removed, including global damage, target-specific damage, speed, boss damage
and gold bonuses. Effects still purchased by other heroes continue to apply.
All hero stats, Total DPS, GoldMultiplier, milestone states and quotes refresh.

HeroService cancels only that hero's pending windup/impact/projectile and returns
it to idle without destroying the model. If attacks are enabled, its next server
update begins a fresh windup; pause/off selections still apply. Start/Stop clean
up the reset listener and retain a single combat dispatcher. Reset controls use
the existing Studio-only remote, exact `ResetHero, heroId` payload, rechecked
IsStudio AND Enabled gate and 0.15s control rate limit. Clients cannot pass a
player, price, level, upgrade set or stat. As with the other debug controls,
any local Studio client may operate the shared scene owner's controls.

### Exact Studio procedure

1. Pull/sync the latest source, set GameConfig.StudioTesting to the following,
   and restart Play:

   ```lua
   Enabled = true,
   StartingGold = 1000000000000,
   StartingHeroLevels = {Knight = 150, Archer = 150, Mage = 150},
   StartingOwnedHeroes = {Archer = true, Mage = true},
   ```

2. Pause ALL attacks in the debug panel. Buy Archer's Rallying Volley and Quick
   Draw, Mage's Enchanted Blade and Alchemical Fortune, and Knight's Treasure
   Hunter. Note gold, wave, enemy HP and all hero levels/stats.
3. Click RESET HERO for Archer. It stays owned at Level 1, its upgrades become
   Locked, its interval returns to 0.7s, and the Archer global damage bonus
   disappears. Knight/Mage levels and purchases, gold, wave and HP stay unchanged.
   Reset Mage: its Knight bonus disappears and Gold Multiplier drops from x1.56
   to x1.25. Reset Knight: multiplier returns to x1. Paused attacks remain paused.
4. On a Level-1 hero, cycle through all six modes and back to x1. With enough
   gold, x10 buys 10, x25 buys 25 and x100 buys 100 (or fewer at the level cap).
   Reset between tests. NEXT at Knight Level 1 reaches 10, then 25, with the
   milestone Available but unpurchased. MAX reaches the configured cap when
   fully funded. At the cap, the purchase button shows Maximum level.
5. For an exact partial-purchase test, stop Play and set StartingGold=492,
   all StartingHeroLevels=1, and StartingOwnedHeroes={Archer=false,Mage=false}.
   Restart and pause ALL **before the first hit** (restart if a reward arrived).
   Select Knight x25: preview should show +17 Levels / 491 Gold. Buy: Level 18
   and 1 Gold. Buying again cannot make the balance negative. For a separate
   NEXT test, restart at Knight Level 17 with a small balance: partial purchase
   stays below 25 and the preview continues targeting 25.
6. Resume attacks; reset Archer while an arrow is in flight. It remains visible,
   the old projectile disappears, and subsequent attacks begin fresh. Repeat
   resets and pause/resume without duplicate hits. Test boss progression and
   the normal shop as before. Restore Enabled=false: no debug/reset panel or
   control remote should exist, while normal bulk leveling remains available.

### Validation

37 standalone Luau simulations passed, executing real source modules with mocked
Roblox APIs: all previous combat/shop/wave/boss/debug/gold regressions, exact
x1/x10/x25/x100 costs and counts, partial x25, exact MAX affordability, all six
requested NEXT starting levels, partial/custom-config/post-final NEXT, no
automatic upgrades, private-state/payload/rate-limit protection, reset isolation
and effect removal, preserved ownership/gold/wave/enemy, UI mode cycling,
reset projectile cancellation and no duplicate dispatcher. All Luau compiles,
Rojo sourcemap and relative require paths are checked. Actual rendering and
replication must still be verified in Roblox Studio. Bulk leveling and hero resets were completed before Phase 6A.


## Phase 6A — central Hub and six claimable islands

The server generates `Workspace.HeroCavesWorld` from `src/shared/WorldConfig.lua`:
one 88x88 Hub, six 64x64 islands on a 150-stud radius at equal 60-degree spacing,
and six 12-stud-wide bridges. Platform tops are at Y=0; bridge tops are recessed to Y=-0.2 to avoid
coplanar overlap at their embedded ends. Island 1 is north
of the Hub; numbering proceeds clockwise to Island 6. Everything is anchored,
temporary Parts. Bridges make claiming reachable by walking without a teleport,
claim button or flight system. This adds a playable floor to a blank place.

WorldConfig controls Hub position/size/spawn, island count/radius/size, starting
angle, optional angular spacing, bridges, zone size/offset and marker offsets.
Leaving AngularSpacingDegrees=nil derives `360 / IslandCount`. All islands use
the same generator; additional named hero markers need only another HeroSlots
entry. Changing size/radius should preserve sufficient bridge/zone clearance.

`IslandService` owns the server-only island records and player-to-island map.
An invisible **ClaimZone** beneath an **UNCLAIMED** sign identifies each free island.
On Touched, the server resolves the current player's character and checks a live
Humanoid with its root physically inside the oriented ClaimZone. It verifies the
island is free and the player has no island, then writes both ownership mappings
without yielding. Near-simultaneous entrants therefore cannot both win: later
callbacks observe the first completed claim. Repeated body-part touches cannot
create another cave or island. No client ownership-request remote exists;
replicated IslandId/OwnerUserId attributes are display data, not ownership state.

Successful claim shows `<DisplayName>'s Cave`, creates
a four-part CavePlaceholder, and selects that island's PlayerSpawn for future
respawns. Claiming does not teleport the walking player. Brief client feedback
reports success, an already-owned island, an occupied island, or full capacity;
notifications are limited to one per player per second to avoid touch spam.
`HeroCavesIslandFeedback` is server-to-client only, with no OnServerEvent handler.

New players always start on the Hub. Their RespawnLocation is assigned server-side,
and a CharacterAdded handler positions the loaded character at the appropriate
spawn (Hub when unowned, own island when owned). Respawning neither releases nor
claims an island and does not duplicate its cave. Stale character callbacks check
player presence, character identity and service generation before positioning.

When an owner leaves, IslandService clears both ownership mappings, resets the
sign/OwnerUserId, destroys the cave, clears the player's IslandId and spawn
reference, and disconnects their character listener. The persistent zone listener
remains available for the next claimant. Rejoining starts unowned at the Hub;
there is no saving. With all six islands occupied, additional players spawn at
the Hub, receive unavailable feedback when entering an occupied zone, and cannot
replace an owner. They can claim a freed island once an owner leaves. Manual
visits to islands are allowed; occupancy is not an access-control system.

### Generated marker structure

```text
Workspace.HeroCavesWorld
  Hub
    Platform
    PlayerSpawn                   (SpawnLocation)
  Bridges
    Bridge1 ... Bridge6
  Islands
    Island1 ... Island6
      Platform
      Markers
        ClaimZone                 (invisible non-colliding touch volume + visible sign)
        PlayerSpawn               (SpawnLocation)
        CavePosition              (invisible anchored marker Part)
        EnemyPosition             (invisible anchored marker Part)
        KnightSlot                (invisible anchored marker Part)
        ArcherSlot                (invisible anchored marker Part)
        MageSlot                  (invisible anchored marker Part)
      CavePlaceholder             (only while claimed)
```

Island models expose `IslandId` and `OwnerUserId` (0 means unclaimed); players
expose `IslandId` only while owned. Server APIs are `GetIsland(player)`,
`GetIslandOwner(id)` and `GetSpawnLocation(player)`. `TryClaim(player,id)` is
server-only and still validates physical presence. Start is idempotent; Stop
releases ownership/connections and destroys only its generated world/notification
remote. Existing combat folders and progression remain independent.

**Combat is still shared temporarily on the Hub at its original position.**
Claiming a cave does not move/spawn heroes, enemies, waves or personal combat.
Phase 6B will perform that separate refactor. The hero upgrade UI and existing
Studio debug tools are unchanged; the debug panel still follows the shared
combat owner, independently of island ownership. There is no shop NPC, cave
upgrade system, DataStore, matchmaking, new hero or final art in Phase 6A.

### Exact Studio test procedure

1. Pull the latest source, run `rojo serve default.project.json`, sync and restart
   Play. The new WorldConfig/IslandService/islands client script must all sync.
   The server now removes old Baseplates/global floor Parts at startup; the
   generated platforms and bridges supply the floor. Existing manual
   spawn pads are not deleted, but server spawn assignment uses the generated pads.
2. Confirm initial spawn at the Hub spawn point, exactly six evenly spaced islands
   and six continuous walkable bridges. Shared Knight/enemy combat remains near
   the center of the Hub. Use a desktop viewport to inspect current prototype HUD.
3. Walk across a bridge and through the zone beneath an UNCLAIMED sign. It should display
   your DisplayName, show claim feedback and create a basic cave. Check the player
   IslandId and island OwnerUserId in Explorer. Walk into a second free zone:
   it remains UNCLAIMED and the feedback says you already own an island.
4. Reset your character: respawn at your owned island with the same ownership and
   one cave. In a fresh unowned client, reset: respawn at the Hub. Inspect all seven
   named markers under each island's Markers folder; no personal combat activates.
5. Use Studio **Test -> Server & Clients** with two players. Have both enter the
   same free zone close together: only one owns it. The loser can claim a different
   free island. Stop the owner client: that island returns to UNCLAIMED and the
   cave disappears. Another unowned client can enter and claim it.
6. For capacity, start a local test with seven clients if your Studio/resources
   support it. Six clients claim distinct islands; the seventh stays unassigned
   and spawns at Hub. Enter an occupied zone for the full-capacity notification.
   Disconnect one owner, then claim the freed island with the seventh client.
7. Run the existing purchases/bulk modes, boss waves, DPS/gold notifications and
   Studio pause/reset tests. For debug controls set StudioTesting.Enabled=true
   and restart Play; restore false afterwards. Island ownership must not change
   hero levels, gold, wave, shared combat ownership or debug behavior.

### Verification and limits

42 standalone Luau simulations passed using real application modules with mocked
Roblox APIs: all 37 earlier regressions plus world geometry/markers/bridges,
validated physical claims and claim races, one-to-one ownership, displays/caves,
Hub/owner respawn, release/reclaim/rejoin, listener cleanup and Stop/Start,
six-island capacity/feedback, and config-driven eight-island/extra-slot generation.
All sources compile; Rojo sourcemap and relative requires are validated. These
simulations do not verify real Touched physics, avatar loading, networking or
visual layout in Studio; use the manual procedure above for those checks.

The temporary bridges have no railings. Falling below the configured void threshold returns the character to its Hub/owned
island spawn; no flight or matchmaking system was added. Ownership is session-only
and depends on server-observed character movement; this is not an anti-teleport
movement validator. Island number/radius/slot configuration is reusable, but final
spacing, cave visuals and future combat positions will need tuning later.
Phase 6B is not implemented.


### Phase 6A geometry correction

The original generated bridges embedded their ends in the Hub/island platforms
while both top surfaces were exactly Y=0. Those coplanar visible top faces can
Z-fight and produce flicker/triangular patterns. The translucent ClaimZone also
had its bottom face at Y=0 (`center Y=4`, `height=8`), coincident with island floor.
The cave's 12-high walls intersected the roof from Y=10 to 12; the side/back walls
also overlapped in the rear two studs, producing coincident outer faces.

`WorldConfig.BridgeSurfaceDrop=0.2` now separates bridge top faces from platform
top faces. Embedded ends remain for uninterrupted collision coverage, with only
a 0.2-stud step. ClaimZone is fully transparent with shadows/query disabled, while
CanTouch stays true and the same server bounds validate claims. Ownership signs
stay visible. SpawnLocations are invisible/non-colliding position references;
platforms supply their floor. Other logical markers remain invisible and now
explicitly have CastShadow=false. Spawn CFrames/RespawnLocation behavior are unchanged.
Cave walls end exactly at the roof underside; side walls end at the back wall's
front edge. The cave retains its four parts and outer footprint/roof height without
intersecting visible surfaces. No additional cave/base floor is generated.

43 Luau simulations pass, including non-overlapping cave geometry, bridge height
separation/collision coverage, hidden markers/zones, claiming and owner/non-owner
respawn, plus all existing regressions. Sources compile and Rojo paths resolve.
For visual verification, stop Play, sync, restart and inspect the six bridge joins,
claim areas and cave joints from several camera angles. Walk the bridges, claim
an island and reset the character. Old running worlds do not regenerate on module
hot reload. The subsequent floating-world correction removes old Baseplate/global floor
Parts at startup, including manually placed legacy floors.
Phase 6B remains outside this correction.


### Floating world only — remove legacy global floors and recover from void

The previous bridge correction left bridge geometry opaque but lowered its top
0.2 studs below platform level. A legacy Studio Baseplate/floor at Y=0 would hide
those bridges and still coincide with Hub/island tops, producing remaining floor
artifacts. No global floor is declared in Rojo or generated by the world service;
the missing step was removal of pre-existing Studio floor geometry. Real Studio
rendering is not available in this cloud environment, so actual Place instances
must be checked using the procedure below rather than assuming their names.

At Start, IslandService now runs `RemoveGlobalFloors()` before creating the world.
It searches Workspace descendants, including nested Models, for anchored, nearly
horizontal floor Parts intersecting the world footprint at/below platform height:

- Baseplate by name, or other configured floor names at least as wide/deep as Hub;
- broad slabs at least 128x128 studs, regardless of name;
- thin relative to their horizontal dimensions (height <= min(width,depth)/4).

WorldConfig contains the names, size threshold and top tolerance. Generated world
Parts are excluded from later cleanup calls. Small props, vertical objects and
geometry far from this world are preserved. Each removed object's full path is
printed in server Output; `HeroCavesWorld.RemovedGlobalFloorCount` records the
startup count. No replacement global floor, catch floor or decorative floor
layer is created: only the seven independent, 4-stud-thick platforms and six
2-stud-thick bridges provide the walkable world. Hub is blue, islands green and
bridges brown, with explicit Transparency=0, collision and no reflectance.
The same bridge spans/end overlaps remain, recessed 0.2 studs to separate top
planes while preserving walkable contact. Cave joints remain non-overlapping.

Claim/spawn/position markers are fully transparent, non-colliding and shadowless;
any child Decal/Texture is also hidden because a transparent Part alone does not
hide its independent texture. Only ClaimZone has CanTouch=true. Ownership signs
remain visible. No translucent technical volume is rendered in normal gameplay.

The server checks living characters every 0.2 seconds. Below Hub surface minus
60 studs, it returns the character to its current server-selected spawn (Hub if
unowned, own island if owned) and zeros linear/angular velocity. Ownership, cave,
levels, gold and wave stay unchanged. Dead/missing characters use normal respawn.
The safety listener is disconnected by IslandService.Stop and recreated once on
Start. VoidDepth/VoidCheckInterval are configurable. No invisible safety floor
was added under the map, so gaps remain empty.

Startup removal happens in the running server copy of a Studio Place. It does not
rewrite the saved edit-mode Place. To remove the same legacy floors permanently
from the editable test Place, sync, stop Play, and run in Studio Command Bar:

```lua
require(game.ServerScriptService.Server.Services.IslandService).RemoveGlobalFloors()
```

Then save the Place. The command uses the same narrow floor rules and prints the
removed paths. If a custom global floor is smaller/named differently, adjust
WorldConfig's explicit floor rules to match it. No global floor assets are stored
in this source repository.

Validation: 46 real-source Luau simulations pass, including named/nested/unnamed
legacy floor removal, preserving props, no generated global slab, seven opaque
thick platforms and six opaque colliding bridges, separated top planes, hidden
spawn textures, functional claim/respawn, unowned/owned void recovery with velocity
reset and all previous multiplayer/progression/debug regressions. Luau compile
and Rojo paths are checked. These are simulations, not actual rendering/physics.

In Studio, stop Play, sync all files and restart. Check Output for removal paths,
then confirm no Baseplate/large floor remains in Workspace during Play. Orbit the
camera below the map: empty space should separate Hub/islands, with six visible
bridges joining them. Walk every bridge, claim, reset, and walk off an edge:
unowned players return to Hub; owners return to their island. Inspect from low
angles for flicker and confirm only ownership signs render above hidden zones.
Re-test competing claims and owner leaving/reclaim. Visual/real humanoid movement
verification still requires this Studio check. Phase 6B remains unimplemented.
