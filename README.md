# Idle Hero Simulator

Roblox/Rojo prototype through **Phase 6C**: a neutral floating Hub, six
claimable floating islands, and independent server-authoritative combat for
every island owner. Each owner has their own heroes, enemy, waves, bosses,
gold and progression. Joining alone starts no combat.

**Phase 6C is implemented:** a Hub Hero Shop NPC reveals/purchases only the next
unowned hero. The temporary HUD now shows only owned heroes and their existing
level/milestone controls. **Phase 6D (clickable physical hero upgrades), saving/
DataStore and offline progress are NOT implemented.** Progress is in memory and
is lost on leaving. Phase 6B was confirmed working in a real Studio two-client
test by the project owner; the new Phase 6C features still require Studio testing.

## Run with Rojo

Use Rojo 7.7.1 and the Studio Rojo plugin:

```sh
rojo serve default.project.json
```

Sync the full project into a test place and start Play. Restart Play after
source/configuration changes: required modules are cached. The server builds
the prototype geometry and combat models; no binary model/place file is required.
`default.project.json` maps Shared to ReplicatedStorage, Server to
ServerScriptService, and Client to StarterPlayerScripts.

## Phase 6C — Hero Shop and sequential discovery

IslandService creates `Workspace.IdleHeroSimulatorWorld.Hub.HeroShop`: seven
anchored, visible, noncolliding Parts form a simple shopkeeper with a HERO SHOP
BillboardGui and `Head.OpenHeroShop` ProximityPrompt. No Toolbox models, final
art or map redesign. Its feet rest on the existing Hub surface without a new
floor layer. The merchant is away from spawn and bridge approaches.

`WorldConfig.HeroShopOffset = Vector3.new(22, 0, 18)` is relative to the Hub's
top surface. `HeroShopActivationDistance = 12` controls both the prompt distance
and the server's root-to-merchant distance validation. E (or normal Roblox
mobile/controller prompt input) opens the personal shop. A living current
character must be within range both to open and to purchase. Leaving range
can keep the view open, but purchases fail without deduction. CLOSE hides it;
avatar respawn closes it. Reopening uses current authoritative ownership.

Startup installs HeroShopService after progression/remotes and before world
generation. IslandService publishes a stable prompt Instance through its
HeroShopChanged event. The shop replaces its old prompt connection when the
world is rebuilt; no mutable ownership/config tables cross BindableEvents.

ProgressionService.GetNextHero(player) walks **HeroConfig.HeroOrder** using
private ownership. With the current unchanged order/values:

| Private ownership | Only offer |
| --- | --- |
| Knight | Archer: 100 Gold, damage 8, 1 / 0.7 = 1.43 attacks/s |
| Knight + Archer | Mage: 1,000 Gold, damage 55, 1 / 2.4 = 0.42 attacks/s |
| Knight + Archer + Mage | ALL HEROES UNLOCKED; More heroes coming later. |

Mage has no locked entry, silhouette, future price or preview before Archer
ownership. The shop UI does not iterate all hero configs: it displays only the
server's current offer. Config/progression metadata is still replicated for
existing tools, so this is intentional UI discovery, not secret assets or an
anti-exploit mechanism. Security comes from private server ownership/order.

### Personal shop state and purchase flow

HeroShopService owns a private record per Player and publishes only their
current offer to `Player.HeroShop`: HeroId/Name, role, configured cost/base damage/
attack speed, AllOwned and OfferToken. Gold is the player's existing EconomyService
balance. HeroShopPanel and `shop.client.lua` create one reusable local ScreenGui;
only the prompt's interacting player receives OpenHeroShop. Client gold and all
offer-attribute changes update affordability/UI even if replication arrives in
a different assignment order. No listener/GUI is added on reopen.

Remotes live in the existing `IdleHeroSimulatorRemotes` folder:

- **OpenHeroShop:** server -> interacting client, no payload; validates distance
  and current live character even if prompt input is forged.
- **PurchaseNextHero(offerToken):** client -> server with **one opaque string**.
  No hero ID, price, target player, levels or ownership are accepted.
- Purchase response: server -> that client, `(success, reason)`.

The private offer token changes after each ownership transition. It is a replay
identifier, not a secret. A delayed duplicate Archer token cannot buy Mage.
Server validation checks exact argument count, player/record, cooldown, token,
live character/distance and the next private hero. ProgressionService performs
the same existing cooldown/affordability validation and atomically deducts the
configured price, grants that next hero, publishes stats and emits HeroOwned
with a Player Instance and hero ID. Failed/stale/skipping/out-of-range requests
do not deduct gold. Neither display attributes nor client affordability are trusted.

On success HeroShopService calls HeroService.RefreshOwnedHeroes for the buyer's
existing context. The new rig is added immediately at ArcherSlot/MageSlot using
the same synchronization routine and existing context update connection. Wave,
enemy, boss deadline, Knight and other players stay unchanged. Without an island,
only ownership changes: no Hub hero/enemy/context is created; claim later spawns
the owned crew. The offer updates in the open shop immediately to Mage or the
all-owned message. Normal Gold HUD also updates from the actual balance.

The old free-choice BuyHero remote/API and BUY HERO branch are removed. Normal
HUD tabs are visible only for owned heroes; all existing owned-hero leveling,
bulk modes and milestone upgrades remain for Phase 6C. Studio debug tools and
testing values remain Studio-gated, with no separate currency or production cheats.

### Exact Phase 6C single-player Studio test

1. In GameConfig set StudioTesting.Enabled=true, StartingGold=2000,
   StartingHeroLevels={Knight=1,Archer=1,Mage=1}, and
   StartingOwnedHeroes={Archer=false,Mage=false}. Pull main, run Rojo, sync the
   **entire** project and restart Play. Required modules are cached per session.
2. Spawn in Hub: no combat. Normal HUD shows owned Knight only; no Archer/Mage
   purchase buttons/tabs. Confirm the visible HERO SHOP merchant at the configured
   diagonal Hub position without blocking spawn or a bridge.
3. Walk within 12 studs, use the E prompt. The centered shop opens and offers
   **only Archer**, damage 8, 1.43 attacks/s, cost 100. No Mage preview anywhere
   in the shop. CLOSE/reopen several times: one GUI and current Archer offer.
4. Buy Archer before claiming. Gold goes exactly 2000 -> 1900; same shop switches
   to Mage (55 damage, 0.42 attacks/s, cost 1K). Archer ownership/tab appears, but
   there is still no Hub hero/enemy/context. Double-click must not buy Mage.
5. Close and claim Island 1. Knight+Archer spawn at their markers; arrows attack
   that island's enemy. Note its Combat.ContextId, Wave, enemy and Knight.
6. Return to the merchant while combat continues. Open and buy Mage: gold drops
   by exactly 1000 from its current value (kills may earn gold during walking).
   Mage immediately appears at Island1.MageSlot without resetting enemy, wave,
   boss deadline or Knight. Exactly one Mage rig; its bolts target A's enemy.
7. The same open shop shows ALL HEROES UNLOCKED and no BUY button. CLOSE/reopen:
   merchant remains usable with that message. Owned hero levels/milestones and
   bulk modes still work in the temporary HUD.
8. Reset the avatar, reopen the shop and confirm session ownership is preserved.
   Repeat from a fresh session with StartingGold=99: Archer BUY is disabled and
   reads NOT ENOUGH GOLD. Claim and earn gold; reopen after returning to Hub:
   affordability must reflect your real current balance. Leave range with shop
   open and try BUY: server rejects it without gold/ownership changes.
9. Restore Enabled=false and temporary values. In a fresh normal session shop
   still works, initial gold is 0, no debug tools/RESET HERO/production cheats.

### Exact Phase 6C two-player Studio test

1. Use the same 2000-gold, level-1, no-Archer/Mage Studio setup above. Sync and
   start **Test -> Server & Clients -> 2 players** (older Studio: Local Server).
   Both players join Hub with Knight owned and no combat.
2. A claims Island 1; B claims Island 2. Confirm independent Combat.ContextId,
   Knight/enemy, waves and deadlines. Both return to the same Hub merchant;
   their islands keep fighting while they are away.
3. In B's client only, open via E and buy Archer, then close. Record B's gold,
   owned Archer rig and context. A has only Knight; B has Knight+Archer.
4. Both open that NPC. A sees Archer; B sees Mage. Opening A's view must never
   open B's view. Mage must not be revealed in A's shop before its purchase.
5. A buys Archer. Exactly 100 is deducted from A's current balance, A gains one
   Archer at Island1.ArcherSlot and A's open shop changes to Mage. B's balance
   has no shop deduction, its ownership/token/rig stay unchanged and its fight
   continues (natural B kills can still add its own gold).
6. Buy Mage separately on each client; each pays 1000 and gains one Mage only
   on its own island. No wave/enemy reset. Toggle A's debug Archer/Mage OFF during
   flight: B's projectiles keep going. Check each client's gold, levels/upgrades,
   total DPS, gold multiplier and boss timer remain owner-specific.
7. Reset A's avatar and fall into void: existing ownership/context remains.
   Close A's client: only Island 1's combat/cave clean up; B continues. B can
   still reopen the all-owned shop. Test island reuse and competing claims as
   in the Phase 6B checks below.
8. Restore testing config. These steps require real Studio; the cloud workspace
   cannot validate prompt input, layout, network latency or engine touch physics.

### Phase 6C regression results and limitations

All **47** source-level scenarios pass: 38 previous regressions plus nine shop
cases covering sequential/live UI, skipping/spoof/replay/range/dead-character
security, insufficient funds/configured order, immediate active-context purchase,
pre-claim purchase/respawn, two-client personal UI, GUI/world/player lifecycle,
production gates/original stats and deferred ownership events. No new per-frame
shop loops or remote broadcasts. Full Luau compilation, Rojo sourcemap and a
Rojo build/XML module validation pass.

NPC and shop visuals are prototype Parts/UI. Heroes and prices are unchanged;
there is no Hero 4. Shared HeroConfig metadata is not concealed from exploiters.
Shop UI can stay open after walking away, but buying requires server distance
validation. Progression/ownership remain session-only. **Phase 6D, saving,
offline progress and final NPC/UI/map art are not implemented.**

## World and island ownership

The Hub and six symmetric islands are independent solid, anchored, colliding
Parts, each 4 studs thick. Six opaque colliding bridges connect them across
empty space. Their walking surfaces sit 0.2 studs below the platform tops;
embedded ends avoid gaps without coplanar top surfaces. There are no decorative
floor layers or generated global floor.

Startup removes legacy anchored horizontal Baseplates/large floors underneath
the generated map footprint, including nested models. It preserves small props,
vertical geometry and distant floors. Output prints every removed object;
`IdleHeroSimulatorWorld.RemovedGlobalFloorCount` records the number removed. Do not
use a global Baseplate or another SpawnLocation for this prototype.

Walk across a bridge and into the inward island claim area below the
**UNCLAIMED** sign. The server checks the live character's root against that
zone; the first valid claimant wins without yielding. One player can own one
island and each island one player. A successful claim changes the sign,
creates the cave placeholder and sets the player's RespawnLocation.

All technical marker Parts and spawn decals are invisible and noncolliding.
ClaimZone remains touch-enabled. Island marker positions come from WorldConfig:

| Marker | Role |
| --- | --- |
| ClaimZone | Server-validated claim detection |
| PlayerSpawn | Character respawn/void return |
| CavePosition | Claimed cave placeholder |
| EnemyPosition | Personal enemy spawn |
| KnightSlot / ArcherSlot / MageSlot | Personal hero rig placement |

The Hub is neutral. Owners resetting/dying return to their own island;
unclaimed players return to Hub. A live character below Y=-60 is returned
to its spawn, with falling/angular velocity cleared. This safety check runs
once every 0.2 seconds and does not change combat or revive a dead character.

## Phase 6B combat architecture

`IslandService` remains the ownership authority. Its server-only **Claimed**
and **Releasing** signals pass `(player, island.Model)`. The combat listener
resolves the actual ownership record from IslandService and then calls
`CombatContextService.StartCombat(player, island)`; release matches the stored
context's Model before `StopCombat(player, expectedIsland)`. `GetContext(player)` exposes
the player's active context to other server services. Duplicate starts are
idempotent; invalid/non-owner starts are rejected.

`CombatContexts` stores private context references keyed by Player. Each includes:

- Player, Island, Active and a unique generation Id;
- its Combat folder with Heroes and Enemies subfolders;
- CurrentWave, CurrentEnemy, pending transition and next-spawn timestamp;
- hero array/map, per-hero animation/target/cooldown state;
- its own wave/hero Heartbeat connections and event subscriptions.

Runtime objects live below:

```text
Workspace.IdleHeroSimulatorWorld
  Hub                         -- no combat here
  Bridges.Bridge1 ... Bridge6
  Islands.Island1 ... Island6
    Platform
    Markers
    CavePlaceholder           -- only while claimed
    Combat                    -- only while personal combat exists
      Heroes.Knight           -- Archer/Mage only if owned
      Enemies.Slime           -- or Boss Slime; absent during wave gap
```

The previous shared combat-owner selection/handoff, global enemy/hero folders,
global combat coordinates and global hero slot offsets have been removed.
Personal progression may exist before claiming, but there is no enemy, hero
rig, wave loop or boss deadline until a confirmed claim. Effective Total DPS
is zero without an active combat area.

The existing services support contexts rather than six duplicated implementations:

| Service | Responsibility |
| --- | --- |
| WaveService | One wave state/update connection per context; own next-wave delay and boss timeout |
| EnemyService | One current enemy reference per context; spawn at its EnemyPosition; own HP/display/death |
| HeroService | One update connection per context; distinct owned rigs, slots and attack state per hero |
| CombatService | Validate hero membership, player/context ownership and the exact captured current enemy before damage |
| EconomyService | Credit the defeated enemy's active context owner only; duplicate reward guard and actual gold-gain popup |
| ProgressionService / UpgradeEffects | Private per-player levels, purchases and calculated stats; owner-specific modifiers and DPS |
| CombatDebugService / CombatDebugState | Studio-only personal controls/snapshots, never a shared combat owner |

Archer arrows and Mage bolts remain server-interpolated prototype visuals.
Each is created under its hero rig, captures the intended enemy reference and
carries OwnerUserId, ContextId, HeroId and TargetEnemyId attributes. Replacement,
death, disabling that hero or cleanup cancels its pending projectile. Damage
checks reject an old enemy, another context's enemy and a released/reused island's
old generation. No combat code selects a global object by hero/enemy name.

Each boss keeps its own absolute deadline on the enemy record. A kill advances
only that context; timeout removes only its boss without reward and schedules
its previous normal wave. No per-frame remote broadcasts or attack-time
Workspace scans are used. Billboard/countdown changes replicate as properties;
boss countdown updates occur only when the displayed second changes.

## Lifecycle and cleanup

Claim creates a fresh context, Wave 1 enemy and currently owned heroes. Buying
Archer/Mage after claim adds exactly one rig on the buyer's island at the next
hero update. Buying before claim changes progression only, then spawns at claim.

CharacterAdded/void recovery changes the avatar location only. Existing context,
wave, enemy, heroes and boss deadline survive avatar reset; no duplicate loops
are created. Combat continues when its owner walks back to Hub/another island.

On leaving or `IslandService.ReleaseIsland(player)`, combat invalidates the
registry entry first, disconnects that context's wave/hero/event connections,
clears pending transitions, destroys its projectiles, rigs, enemy and Combat
folder, and clears personal debug state. IslandService clears ownership, cave,
label and respawn reference. Other owners keep their contexts. A later claimant
starts at Wave 1 with a new generation Id. Ownership validation also blocks
stale attacks while deferred release callbacks await delivery.

`CombatContextService.Stop()` cleans all registered contexts; `Start()` can
reconnect and initialize currently claimed islands. Manual release retains the
player's character lifecycle listener for subsequent claims.

## Existing combat and progression rules

No HP, damage, price, reward, milestone, animation or attack timing rebalance
was made in Phase 6B. Defaults remain:

| Hero | Initially owned | Unlock gold | Base hit | Attack interval | Damage growth | Base level cost |
| --- | --- | --- | --- | --- | --- | --- |
| Knight | Yes | 0 | 20 | 1.3s | 1.08 | 10 |
| Archer | No | 100 | 8 | 0.7s | 1.08 | 15 |
| Mage | No | 1,000 | 55 | 2.4s | 1.09 | 40 |

All level costs grow by 1.12; the configured maximum level is 200. Enemy base
HP is 20, HP growth 1.18, every fifth wave a boss with HP x10 and 30 seconds
to defeat it. Wave 1–4 HP: 20, 24, 28, 33; Wave 5 boss HP: 330.
Base gold is 5, grows by 1.15 each wave; bosses multiply this value by 5
before rounding. Existing rounding is preserved (Wave 5 boss reward: 44).

Knight's sword uses 0.28s wind-up, 0.16s swing, impact at 0.44s, 0.14s
follow-through and 0.32s recovery. Each attack applies one authoritative impact.
Ranged heroes preserve their own timings. Speed bonuses accelerate both
cooldown and animation; attacks already in flight keep their captured speed.

Leveling unlocks milestones; effects require a separate successful purchase.
HeroDamageMultiplier, GlobalHeroDamageMultiplier, SpecificHeroDamageMultiplier,
AttackSpeedMultiplier, BossDamageMultiplier and GoldMultiplier all stay within
the purchasing player's progression. “Global” means all that player's heroes.
Normal DPS excludes boss-only effects. Gold bonuses multiply together and apply
to enemy earnings, not starting gold; popups show only the actual capped gain.

### Knight milestones

| Level | Upgrade | Effect | Gold cost |
| --- | --- | --- | --- |
| 10 | Sharpened Blade | This hero damage x2 | 100 |
| 25 | Knight Training | This hero damage x2 | 1,000 |
| 50 | Treasure Hunter | Personal gold earned x1.25 | 10,000 |
| 100 | Sword Mastery | This hero damage x5 | 1,000,000 |
| 150 | Battle Inspiration | All your heroes damage x1.25 | 100,000,000 |
| 200 | Legendary Knight | This hero damage x10 | 10,000,000,000 |

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

The temporary HUD retains **owned-hero** tabs, milestone buttons and
bulk modes x1/x10/x25/x100/MAX/NEXT. NEXT targets the next configured milestone;
bulk buys sum the increasing rounded per-level costs and may buy a partial
count if funds are insufficient. Unlocking a milestone never buys it automatically.

Purchase remotes accept only IDs/modes. The server validates payload length/types,
known heroes/upgrades, private ownership, affordability, level requirements,
level cap, already-purchased state and rate limits. Client display attributes,
prices, damage and target players are not authoritative inputs.

## Configuration and Studio tools

| File | Configuration |
| --- | --- |
| src/shared/WorldConfig.lua | Hub, islands, bridges, invisible marker offsets and void recovery |
| src/shared/GameConfig.lua | Wave delay, boss cadence/time limit, economy limits and StudioTesting |
| src/shared/EnemyConfig.lua | Enemy HP/reward/appearance |
| src/shared/HeroConfig.lua | Hero stats/prices/milestones/appearance/animation |

Studio tools require both `RunService:IsStudio()` and
`GameConfig.StudioTesting.Enabled = true`. Their controls and RESET HERO do not
exist in production. With testing enabled, the local debug panel reads
`Players.LocalPlayer.IdleHeroSimulatorCombatDebug`; its Control remote lives in
ReplicatedStorage.IdleHeroSimulatorCombatDebug. Caller identity determines the context;
payloads cannot specify another player. Without an island it displays
**NO ACTIVE COMBAT AREA** and actions do nothing.

Pause All, Knight/Archer/Mage ON/OFF, Reset current enemy HP and RESET HERO
operate only on the caller. Pausing cancels pending attacks but does not pause
boss deadlines. HP reset preserves the wave and boss deadline. RESET HERO
restores that hero's level 1 and clears its purchased upgrades without changing
ownership/gold/wave/other hero levels; any cross-hero effects originating from
those cleared upgrades are recalculated. Gold Multiplier and Total DPS update
from the caller's real progression.

## Exact single-player Studio test

1. Pull this revision, run Rojo, sync the entire project. Leave StudioTesting
   disabled initially; Play. Spawn in Hub with no heroes/enemies/Combat folders.
   Confirm the Hub, all six islands and visible bridges over void. Walk across
   a bridge; technical marker Parts must not render or flicker.
2. Enter Island 1's UNCLAIMED claim zone. Its sign changes, cave appears and
   `Island1.Combat` contains Knight and the Wave 1 Slime. Inspect rig/enemy
   positions against KnightSlot/EnemyPosition and OwnerUserId/ContextId.
   Walk into another zone: no second ownership/context. Stay in the first zone:
   no duplicate Knight/enemy/loops.
3. Watch waves, HP hits, personal gold and gold popup. Wave 2 should go 24 -> 4
   at the first sword impact. Wave 5 has 330 HP/30s; default Knight defeats it
   and advances to Wave 6. No enemy/hero appears in Hub.
4. Reset the avatar during combat (also during a boss). Return to Island 1;
   wave, Combat folder, rigs, enemy and absolute boss deadline persist. Jump
   off the island: return safely to its spawn without combat restart. Restart
   Play and fall before claiming: return to Hub.
5. Stop Play. Set StudioTesting Enabled=true, StartingGold=2000,
   StartingHeroLevels={Knight=1,Archer=1,Mage=1},
   StartingOwnedHeroes={Archer=false,Mage=false}. Sync/restart. Debug says
   NO ACTIVE COMBAT AREA; pause/reset actions in Hub have no effect. Walk to the Hub merchant, press E and buy Archer
   for 100 before claiming; no physical hero spawns yet. Claim Island 1:
   Knight+Archer spawn. Return to the Hub merchant and buy Mage for 1000: exactly one Mage appears at MageSlot.
   Observe arrows/bolts hit only this island's captured enemy.
6. Level each hero separately through x1/x10/x25/x100/MAX/NEXT; inspect exact
   counts/costs, partial affordability and milestone availability. For fast
   upgrades, stop Play and use StartingGold=1000000000000 and all three starting
   levels=150, with Archer/Mage owned. Sync/restart and claim. Buy Archer Quick
   Draw/Rallying Volley/Giant Slayer, Mage Enchanted Blade/Alchemical Fortune
   and Knight Treasure Hunter. Check personal attack speed, Knight cross bonus,
   normal-vs-boss damage, Gold Multiplier 1.5625 and a Wave 5 reward of 69 when
   these gold upgrades are active before the kill. No milestone activates
   merely from the starting level.
7. Use debug pause/toggles/HP reset. Pending disabled projectiles disappear;
   paused heroes deal no damage, boss time still expires. RESET HERO on a
   selected hero restores level 1 and removes its purchased bonuses only.
8. For deterministic timeout, restart with level-1 Knight only, claim and pause
   attacks after reaching Boss 5. At 30s it disappears, grants no gold and
   returns to Wave 4. Alternatively temporarily set Knight BaseDamage=5, test,
   then restore it to 20. Reset enemy HP must not extend the deadline.
9. Restore StudioTesting.Enabled=false and all temporary stat/config changes.
   Sync/restart: debug controls/reset shortcuts must be absent.

## Exact two-player Studio test

1. Set StudioTesting Enabled=true, StartingGold=1000000000000, all starting
   levels=1 and StartingOwnedHeroes={Archer=false,Mage=false}. Sync. Use Studio
   **Test -> Server & Clients**, choose **2 players**, Start (older Studio:
   Local Server with 2 clients). Both clients start in Hub without combat.
2. In client A, walk to and claim Island 1. A gets its Knight/Slime/Wave 1;
   client B stays in Hub with no combat and NO ACTIVE COMBAT AREA. In client B,
   claim Island 4. Server Explorer now shows two separate Combat folders with
   distinct OwnerUserId/ContextId and one Knight/enemy each.
3. Pause B using B's debug panel. Let A progress; B's wave/HP/gold stay unchanged.
   Resume B after several seconds: both fight with different wave/HP and boss
   deadlines. A's kill advances/rewards A only. Pause A at Boss 5 until timeout;
   only A returns to Wave 4 without reward while B keeps its own fight.
4. Return each avatar to the Hub merchant and buy Archer, then Mage, via E. Check separate rig/projectile instances
   in each Combat folder, correct slots and projectile TargetEnemyId. Toggle
   A's Archer/Mage OFF during flight: A's projectiles disappear; B's continue.
   A replacing/killing an enemy must never redirect an old projectile to its
   next enemy or to B. Confirm B's gold popups are only from B's kills.
5. On A only, level Archer to 50 and buy Quick Draw/Rallying Volley; level Mage
   to 150 and buy Enchanted Blade/Alchemical Fortune; level Knight to 50 and buy
   Treasure Hunter. A's effective speed/damage/GoldMultiplier/Total DPS change;
   B's levels, purchased upgrades and multiplier remain unchanged. Compare
   normal and boss damage after A buys Giant Slayer at Archer level 150.
6. Pause/toggle/reset enemy HP/RESET HERO in A's panel. B's state stays unchanged
   apart from its own natural combat updates. Verify RESET HERO affects only
   A's selected hero and recalculates A's originating cross/global effects.
7. Reset A's avatar during a boss and jump into void. A returns to its island;
   its same context, wave, rigs, enemy and boss deadline survive. B continues.
8. Close A's client. Server Explorer must show Island 1 UNCLAIMED without its
   CavePlaceholder/Combat folder; B keeps fighting on Island 4. In the server
   Command Bar use `local s=require(game.ServerScriptService.Server.Services.IslandService);
   s.ReleaseIsland(game.Players:GetPlayers()[1])` for the remaining B player.
   B's context/cave are cleaned without removing its progression. In B's
   client, claim freed Island 1: a fresh context starts at Wave 1 with B's
   owned heroes and a new ContextId. There are no A rigs/arrows/enemies.
9. In a separate six-client run, claim all six islands and buy both ranged heroes.
   Buy heroes at the Hub merchant before returning to the islands.
   Confirm six independent contexts/18 hero rigs; a seventh client cannot claim
   until one is released. Two clients entering the same free zone must produce
   one owner and one context. Restore testing configuration afterward.

## Automated verification and limits

`tests/phase6b.py` loads the actual current modules and executes all 38 prior
regressions against `tests/roblox_mock.luau`. The two obsolete purchase tests were
migrated to the new shop request; their ownership/security/claim assertions remain.
`tests/phase6c.py` runs those 38 plus nine new shop scenarios: **47 passed**.
Existing progression/security cases are in `tests/progression_regressions.json`.
The mock preserves BindableEvent table copying and now routes FireClient only to
that simulated client's listeners. Run with Python 3 and a Luau CLI:

```sh
LUAU_BIN=/path/to/luau python3 tests/phase6b.py
LUAU_BIN=/path/to/luau python3 tests/phase6c.py
luau-compile src/shared/*.lua src/server/*.lua src/server/Services/*.lua src/server/Heroes/*.lua src/client/*.lua
rojo sourcemap default.project.json --output /tmp/idle-hero-simulator-sourcemap.json
```

The 38 scenarios passed during Phase 6B implementation: neutral Hub, claim
startup/races, marker placement, single-player waves/bosses, two-player damage
and projectile isolation, real attack speeds/upgrades, independent deadlines
and rewards, gold caps/duplicate death notifications, purchases before/after
claim, personal debug/security, avatar reset/void, cleanup/reclaim, deferred
lifecycle notifications, six simultaneous contexts, stale/long-frame hits,
production gates, bulk/progression regressions, legacy-floor removal and
invisible markers/opaque bridges. All Luau sources compile and Rojo's sourcemap
resolves the new modules. Phase 6C also passed a Rojo 7.7.1 build and XML
validation of all 27 scripts/modules (including HeroShopService, HeroShopPanel
and the shop LocalScript). The temporary build artifact was removed; no model/
place files are added to the repository.

These automated results are source-level simulations. The project owner has
subsequently verified Phase 6B in a real two-client Studio test. New Phase 6C
client/server behavior has **not** yet been verified in Studio by this workspace.
The cloud workspace cannot run Roblox Studio. Actual rendering, bridge walking,
touch physics, replication latency and local-server clients need the manual
procedures above. Projectile visuals remain server-replicated placeholders;
client VFX, streaming behavior and production-scale performance are unverified.
Ownership/progression is session-only, at most six players can own islands,
and the first valid claimant wins. Phase 6D remains unstarted.


## Phase 6B Studio runtime integration correction

The original claim event sent the Lua `island` ownership table. Roblox copies
Lua tables passed through BindableEvent. Its receiver therefore saw a different
table, and `IslandService.GetIsland(player) ~= island` caused StartCombat to
return before creating a context. Claim labels/caves still worked, but there
was no enemy/Knight/wave or active state for the client. The previous mock passed
the same table reference; its 35 tests missed this engine behavior.

Claim/release events now pass the Player and island Model Instances, which keep
identity across events. Listeners resolve the private ownership record instead
of trusting a copied table. Enemy Changed similarly passes Player/ContextId.
Enemy Defeated passes Player/ContextId/sequence; its reward is stored privately
in that context and consumed once by EconomyService. No island, enemy or context
state table crosses these production BindableEvents. This also fixes projectile
cancellation and reward checks that previously depended on table identity.

Startup order was already correct and remains Economy -> Progression -> Combat
listeners/reconciliation -> Studio debug -> IslandService/touch handlers. Start
is idempotent and reconciles existing ownership. Marker/default Knight validation
reports exact failures; unexpected startup errors clean up partial combat and
restore inactive state. Registry changes publish HasCombatArea/TotalDPS; successful
physical startup explicitly refreshes progression again. The existing client
attribute listener changes its claim prompt without trusting client ownership.

Studio-only Output diagnostics show: listeners ready, claim confirmed/received,
marker/default Knight validation, context ID/Wave 1 startup, and spawned enemy/
Knight with active state/TotalDPS. Failure logs start with
`[CombatContext] START FAILED:` and include the precise reason/traceback.
These diagnostics do not run each frame/attack and are absent outside Studio.

The corrected mock copies plain tables while preserving mock Instance/value
identities. Before the production fix, 33 of the existing 35 scenarios failed
with this semantics change, reproducing the missing claim startup. All existing
cases now pass. Three new cases test the actual two-player Touched -> real module
BindableEvent path -> ownership/context lookup -> enemy/Knight -> UI/DPS, stable
enemy notifications/private one-shot rewards, and marker/error rollback plus
startup reconciliation. The probe explicitly verifies that a delivered Lua table
is a copy while its nested Model/Player Instances are the same references.

For the real Studio retest, synchronize **all** server/client/shared modules and
restart the session. Start two clients with StudioTesting disabled. A claims
Island 1: Output must show the complete diagnostic chain, Island1.Combat must
contain Knight and a Wave 1 enemy, HasCombatArea must be true and TotalDPS about
15.3846. The claim prompt changes; B still has no context/DPS. B then claims
Island 2 and gets its separate Wave 1/Knight/enemy. Continue with the full
single/two-player tests above, including owner-only gold/projectiles and release.
The cloud regression is not a completed Studio retest; rendering/network/physics
confirmation for new changes still requires Studio. Phase 6D remains unstarted.


To verify the event boundary in the **real Roblox engine**, paste
`tests/studio_claim_integration.lua` into the **server** Command Bar after starting
the two-client session and before claiming. With default level-1 Knight and
StudioTesting disabled, it first checks real table-copy/Instance-identity semantics,
then observes the actual claim event (without forcing claims) and asserts each
player's authoritative context, Wave 1 enemy, Knight positions and active/DPS
attributes. Claim islands within 120 seconds; successful Output ends with
`[Studio regression] PASS: both actual claims started separate combat`.
This script is not mapped by Rojo and has not been executed here; it is a Studio
regression procedure, separate from the 38 completed cloud simulations.
