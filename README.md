# Idle Hero Simulator

Roblox/Rojo prototype through **Phase 6D.1**: a neutral floating Hub, six
claimable floating islands and independent server-authoritative combat for
every island owner. Each owner has their own heroes, enemy, waves, bosses,
gold and progression. Joining alone starts no combat.

**Phase 6D is implemented:** interact with a physical owned hero to open its
contextual upgrade menu. Normal gameplay keeps only compact Gold and Total DPS,
plus reward popups. The separate Hub Hero Shop still discovers Archer -> Mage.
**Saving/DataStore and Offline Progress are NOT implemented.** Progress is in
memory and is lost on leaving. The project owner confirmed Phases 6A, 6B, 6C
and 6C.1 working in real Studio multiplayer tests, and Phase 6D working in real
Studio testing. New Phase 6D.1 positioning/prompt filtering still needs Studio checks. Reliable 10 Hz claim fallback remains intact.

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

## Phase 6D.1 — left menu and owner-only upgrade prompts

Only two UX changes were made. The contextual menu now anchors at (0,0) and starts
at screen offset **(16,72) pixels**, with its existing 360-pixel width and size
constraints. Its height uses 0.8 of the viewport minus 72 pixels. Knight, Archer
and Mage reuse this same panel/position; contents, purchases and live updates
are unchanged. Compact Gold remains at (16,12), 36 pixels high, ending at Y=48:
there is a 24-pixel gap before the menu. Gold/Total DPS positioning was not changed.

HeroPromptVisibility runs once per local player. It recognizes only the existing
physical UpgradeHero ProximityPrompts and reads the nearest ancestor Model's
existing replicated **OwnerUserId, HeroId and ContextId** attributes. These are
safe public identifiers, not private progression/selection state. Locally, Enabled
is true only when the owner UserId matches LocalPlayer and hero/context identifiers
have arrived. Missing ownership/context metadata fails closed. These local writes
never change the server's Enabled value or another client's view.

The filter subscribes to Workspace.DescendantAdded before one startup scan of
existing prompts. Newly claimed/purchased/recreated heroes are handled by that
event; attribute changes handle delayed metadata. Prompt ancestry changes rebind
the model reference; removal disconnects its property/ownership listeners. An
Enabled-property listener reapplies filtering after replication updates. No
heartbeat/poll loop, hero-name search or extra remote is added. The shared
OpenHeroShop prompt is ignored and remains available to everyone.

HeroUpgradeService, HeroService ownership assignment and ProgressionService
security were not changed. Foreign prompt interaction and purchase requests still
fail the existing private owner/context/physical-instance/token checks. Hiding
prompts is UX only; a modified client cannot bypass the server validation.

Changed: src/client/main.client.lua, new src/client/HeroPromptVisibility.lua,
tests/phase6b.py, tests/roblox_mock.luau, new tests/phase6d1.py and README.md.
The mock now separates each client's local Enabled overrides from server state
and executes event callbacks in their registered client/server scope. All **78**
scenarios pass: all previous 74 plus four tests covering left position/hero switch,
owner-vs-foreign views/server rejection/shared shop, dynamically purchased heroes/
context recreation/release/reuse, and delayed metadata/listener cleanup. Full
Luau compilation, Rojo sourcemap and temporary build/XML validation of all 30
script instances pass (server/client main are counted separately). No place/model artifact is committed.

### Exact Phase 6D.1 Studio verification

Pull main, run Rojo 7.7.1, sync the entire project and restart Play. Start two
clients. For affordable Archer/Mage tests use the existing StudioTesting mode
with StartingGold=2000, level-1 heroes and no starting Archer/Mage; restore defaults
afterward. The existing Studio debug panel is expected only in testing mode.

1. Start two clients A/B in Hub.
2. Both claim different islands.
3. A approaches A's Knight.
4. A sees its Upgrade prompt and can open the menu.
5. B approaches A's Knight.
6. B must see no hero Upgrade prompt.
7. B approaches B's Knight.
8. B sees its own Upgrade prompt and can open the menu.
9. A approaches B's Knight.
10. A must see no hero Upgrade prompt.
11. A buys Archer from the Hub shop.
12. A returns to Archer and sees its Upgrade prompt.
13. B approaches that Archer and sees no Upgrade prompt.
14. Repeat with Mage; verify owner-only visibility without rejoining.
15. Confirm the Hub Hero Shop prompt remains visible/usable by both clients.
16. Server validation is still present: from the **server** Command Bar, resolve
    A/B by their actual test-player names (replace Player1/Player2 as necessary)
    and attempt a foreign hero interaction directly:

    ```lua
    local services = game.ServerScriptService.Server.Services
    local a, b = game.Players:FindFirstChild("Player1"), game.Players:FindFirstChild("Player2")
    assert(a and b, "Use the actual test-player names")
    local context = require(services.CombatContexts).Get(a)
    local hero = context.HeroesById.Knight
    b.Character:PivotTo(hero.Model.PrimaryPart.CFrame)
    assert(require(services.HeroUpgradeService).Open(b, hero) == false)
    print("PASS: foreign interaction rejected by server")
    ```

17. Return to your own Knight and open its menu.
18. Confirm the menu starts on the left with a 16-pixel edge margin.
19. Confirm gameplay center stays clear; switch to Archer/Mage and check the
    same menu position and unchanged stats/bulk/milestones/CLOSE/live updates.
20. Confirm Gold stays readable above the panel and Total DPS remains upper right.

Also leave/reuse an island or recreate a context: new owner prompts must update
without rejoin; old prompt listeners must not retain stale visibility. Continue
Phase 6D's single-/two-player regressions below. Cloud tests do not validate actual
Roblox prompt rendering, metadata replication timing or viewport overlap; those
require these real Studio checks. **Saving/DataStore and Offline Progress are
NOT implemented.** No new heroes, map redesign or final UI redesign.

## Phase 6D — interact with a physical hero to upgrade

HeroService calls HeroUpgradeService.Attach immediately after registering each
physical rig in its private context.HeroesById. Exactly one UpgradeHero
ProximityPrompt is attached to the model's PrimaryPart (the existing invisible
rig root): ObjectText=hero name, ActionText=Upgrade, E, HoldDuration=0,
RequiresLineOfSight=false. WorldConfig.HeroUpgradeActivationDistance=10 controls
prompt and server root-to-hero distance. Roblox supplies mobile/controller input.
No global Workspace hero-name lookup is used. Knight startup, pre-owned crews,
newly purchased Archer/Mage and regenerated contexts use the same spawn path.

HeroUpgradeService starts after ProgressionService and before combat/world startup.
It captures the actual server hero record in each prompt callback. Opening requires
an active private context belonging to the interacting Player, the exact
HeroesById entry/model in that context's HeroFolder, valid hero ID, private owned
progression, enabled instance-bound prompt, and a living character/root within
10 studs. A foreign or unowned hero opens nothing and exposes no other player's
progression. Phase 6D.1 hides visitors' hero prompts locally; server rejection stays authoritative.

### Selection and purchases

One private selection per player stores the exact hero record and a monotonically
changing token. Player.HeroUpgradeSelection replicates Token, HeroId and ContextId
for inspection; these attributes are not validation authority. OpenHeroUpgrade
sends only that player the stable Model Instance, HeroId and token. A new physical
interaction replaces the selection/token. The client reuses one menu, rebuilding
only that hero's milestone rows; there are no hero-selection tabs.

The existing purchase remotes now require the selection token:

| Remote | Client arguments |
| --- | --- |
| BuyHeroLevels | heroId, mode, selectionToken |
| BuyHeroLevel (x1 compatibility) | heroId, selectionToken |
| BuyUpgrade | heroId, upgradeId, selectionToken |
| CloseHeroUpgrade | selectionToken |

ProgressionService's remote adapter validates exact argument count and delegates
selection validation to HeroUpgradeService before calling the unchanged
BuyHeroLevels / BuyHeroLevel / BuyUpgrade functions. The private player selection,
hero ID/token, current live character/root, active owning context, exact physical
model, current HeroesById record and private ownership must all still match.
No client cost, amount, milestone state, target player or replicated ownership is
trusted. Direct server APIs remain available for existing trusted systems/tests;
remote purchases without a valid physical selection are rejected. Server prices,
rounded costs, actual count, level caps, ownership checks, milestone effects and
shared purchase cooldown are unchanged. Replies carry the selection token so
late results for an old hero do not overwrite the current menu's feedback.

Close revokes only the matching selection token. Model removal/reparenting,
HeroService cleanup, context invalidation, island release, departure and avatar
reset invalidate the selected instance and safely close the menu. Late ancestry
callbacks or close messages for an old selection cannot close a new one. The
private context check blocks purchases even before deferred release cleanup.
Prompt and model listeners disconnect on removal; recreated rigs get fresh prompts.

Distance is checked on opening. A valid menu may stay open while walking away
or being returned from void; purchases still require the same active owning
context, physical hero and living avatar. No movement/camera locks or combat
pause/restart are introduced. Resetting the avatar closes the menu while keeping
its existing combat/hero instances. Studio RESET HERO updates an open menu
without closing it because the physical hero itself remains valid.

### Contextual menu and compact permanent HUD

The existing client/main.client.lua now keeps one normally hidden left-side Panel
inside IdleHeroSimulatorProgression. It shows the selected hero's name, level,
damage, attack speed in attacks/sec, DPS, personal Gold Multiplier, single next
level cost, selected bulk quote, mode/Level Up buttons, own milestone rows and
CLOSE. Only server-published HeroProgression snapshots/quotes supply calculations;
HeroConfig supplies names/milestone metadata, not duplicate client damage formulas.
Gold, level, upgrade, quote, cross/global effect and DPS attributes refresh the
open menu without reopen. Milestones stay LOCKED / AVAILABLE / PURCHASED.

The former permanent left panel, hero tabs and combat explanatory block are gone.
The ScreenGui stays enabled for its separate compact Gold (upper left), Total DPS
(upper right), GoldPopup and existing Studio-only CombatDebugPanel. Closing the
hero menu hides only Panel, so actual reward popups/gold/DPS continue independently.
The separate HeroShopPanel and NPC prompt preserve island-gated sequential
Archer -> Mage discovery. Buying a hero immediately adds its physical upgrade
prompt to the existing island context without resetting enemy/wave/deadline.

All six modes remain x1, x10, x25, x100, MAX, NEXT (the mode button cycles them).
MAX buys the maximum affordable consecutive levels; NEXT targets the next
configured milestone and falls back to x1 after the final milestone, subject to
the existing level cap. Neither automatically buys a milestone. Upgrades remain
personal and use existing local, cross-hero and global effects. The open menu
updates for Studio RESET HERO; pause/toggles/enemy HP reset/debug snapshots are
still Studio-only and separate from production UI.

### Exact Phase 6D single-player Studio test

Pull main, run Rojo 7.7.1, sync the **entire** project and restart Play after every
config change. For affordable prototype tests set StudioTesting.Enabled=true,
StartingGold=1000000000000, StartingHeroLevels={Knight=1,Archer=1,Mage=1},
StartingOwnedHeroes={Archer=false,Mage=false}. The large Studio debug panel is
expected in this mode. Test production HUD separately with Enabled=false.

1. Join the game in Hub without combat.
2. Claim an island by normal walking; confirm owner avatar/name and Wave 1 crew.
3. Confirm compact permanent Gold and Total DPS, with no permanent hero controls.
4. Confirm there are no hero tabs/old left progression panel. Studio debug UI is
   independent and only visible while StudioTesting is enabled.
5. Walk within 10 studs of your physical Knight.
6. Press E on its Upgrade prompt (or the platform's prompt input).
7. One Knight menu opens on the left, with CLOSE and only Knight milestones.
8. Compare Level/Damage/Attack Speed/DPS to your HeroProgression.Knight attributes;
   default level 1: Damage 20, speed 0.77 attacks/sec, rounded displayed DPS 15.
9. In x1 mode buy one level; compare gold deduction with the server quote.
10. Confirm level, damage, DPS and costs update immediately without reopening.
11. Cycle to x10 and buy; compare the server's actual count/total cost.
12. Cycle to MAX and buy; it uses the existing level cap/affordability. If MAX
    reaches the cap, use Studio RESET HERO before the next NEXT test.
13. Cycle to NEXT and buy; it targets the next milestone, buying only levels.
14. At a required level buy a Knight milestone explicitly.
15. Confirm its button becomes PURCHASED, its effect updates and duplicates fail.
16. Close the menu: permanent Gold/Total DPS and reward popups remain available.
17. Confirm attacks, wave transitions, boss timer and movement never stopped.
18. Return to the Hero Shop and buy the next Archer offer normally.
19. Confirm one Archer spawns on your island with exactly one Upgrade prompt.
20. Interact with your Archer.
21. Its menu shows Archer stats/milestones, not locked/unowned heroes.
22. Open Knight then Archer while the panel is open: one menu replaces contents.
23. Buy an Archer level with x1.
24. Confirm only Archer's level changes. Repeat purchasing/interacting with Mage;
    test Mage's cross/global upgrades live in another hero's open menu. RESET
    HERO on the selected hero must show Level 1/cleared milestones/current stats
    while keeping the menu open. Reset the avatar/release the island/despawn the
    model: the menu must close safely. Fall into void and verify proper respawn.

Restore StudioTesting.Enabled=false and temporary values, sync/restart. Gold
starts at 0; only Gold/Total DPS/reward popups remain permanent, and Studio debug
controls/RESET HERO are absent. Claim/open Knight and verify normal gameplay again.

### Exact Phase 6D two-player Studio test

Use the same testing configuration, sync/restart and Test -> Server & Clients:

1. Start two clients A/B in Hub without combat.
2. Both claim different islands with independent ownership/portraits.
3. Confirm each has one physical Knight with one Upgrade prompt.
4. A interacts with A's Knight.
5. A sees A's hero progression only; B's menu stays hidden.
6. B interacts with B's Knight.
7. B sees B's progression; both menus can be open independently.
8. Close A's menu and walk A to B's island.
9. A attempts B's Knight Upgrade prompt.
10. No menu opens for A and B's menu/selection remains unchanged.
11. Return A to A's Knight, open and level it.
12. B's Knight level/milestones stay unchanged (natural combat gold may change).
13. B levels B's Knight separately.
14. A's level/milestones stay unchanged; compare different levels in both menus.
15. A alone buys Archer from the Hub shop.
16. Only A's Archer appears; A can upgrade it and B's interaction is rejected.

Also test own milestones, active boss countdown, selected RESET HERO, avatar
reset, void return, owner leaving, freed island reuse and simultaneous claim
safety. A selected hero's cleanup closes only its owner's menu. With six clients,
claim all islands: 18 prompts with all three heroes owned, six private selections
and independent purchases; no global name lookup or shared selection/state.

### Validation and limitations

All **74** actual-module scenarios pass: all 61 prior claim/combat/progression/shop/
UI regressions plus 13 Phase 6D cases for own/foreign/unowned interaction, distance/
payload/token spoofing, all bulk modes, own milestones/live global effects/reset,
hero switch/close/stale results, despawn/context recreation, avatar/void, purchased/
pre-owned rigs, combat/reward continuity, six owners, two client-script instances,
and deferred old callbacks/release cleanup. Earlier remote tests now supply a real
physical selection/token; their malformed requests, private state, cost/rate and
ownership assertions remain. Those fixtures freeze their attack heartbeat while
retaining the physical hero instead of destroying it. Old permanent-tab assertions
now check hidden/no-tabs UI and physical interaction instead.

Full Luau compilation, Rojo sourcemap and temporary Rojo build/XML validation of
all 28 scripts/modules pass; no place/model artifact is committed. The tests use
real modules with deterministic API mocks, not Studio rendering/replication/physics.
Real E/mobile prompt selection, UI overlap/readability, actual thumbnail loading,
network latency and destruction event timing still require the manual tests above.
UI is prototype-quality; costs/stats remain rounded by the existing formatter.
Saving/DataStore, Offline Progress, new heroes and map/art redesign are absent.

Created: src/server/Services/HeroUpgradeService.lua, tests/phase6d.py.
Modified: src/server/Services/{HeroService,ProgressionService}.lua,
src/server/main.server.lua, src/client/main.client.lua, src/shared/WorldConfig.lua,
tests/{phase6b,phase6c}.py, tests/roblox_mock.luau and README.md.

## Claim responsiveness fix — retained in Phase 6D

The previous implementation relied exclusively on ClaimZone.Touched. Its callback
accepted any part of the current character (not just HumanoidRootPart), but
TryClaim required the live HumanoidRootPart's center inside the oriented zone.
An early foot/limb touch could therefore fail while the root was outside, with
no scheduled retry after the root entered. Missed physics touch events had the
same effect. This is the likely cause of the reported Studio delay; no actual
Studio physics trace was captured in this cloud workspace.

Inspection confirmed CanTouch=true, CanCollide=false and CanQuery=false on the
invisible zone. CanQuery does not affect the new mathematical position test.
There was no claim polling. ClaimFeedbackCooldown=1 throttles messages only,
not ownership attempts. The CharacterAdded handler's 10-second WaitForChild
timeout is solely for spawn positioning; claim validation does not wait. Zone
touch handlers and combat subscriptions are installed before claims are enabled.

Both Touched and the new occupancy detector call the same server-only TryClaim
function. Every WorldConfig.ClaimCheckInterval=0.1 seconds (10 Hz), the existing
world Heartbeat checks registered, present players with live characters and no
private island record. It tests their root position against direct references
to the six free zones using CFrame:PointToObjectSpace. No Workspace scans,
spatial-query dependencies, extra heartbeat connection or per-frame remote
broadcasts are introduced. Nominal fallback latency is one 0.1-second interval
plus Heartbeat scheduling; real server load/replication still need Studio checks.
Successful automatic claims print their detection path in Studio only; polling
does not print on every check or repeatedly try occupied zones.

ClaimZone geometry is unchanged: 20 x 8 x 12 studs, centered at island-local
(0,4,-22), spanning X=-10..10, Y=0..8 and Z=-28..-16. It covers the normal
bridge-side walking entrance and ordinary root height without making the entire
island a claim area. It remains transparent, noncolliding and touch-enabled;
no rendered layers/floor surfaces were added.

TryClaim revalidates the player, live character/root, exact zone, private existing
ownership and free island. Both ownership writes happen without yielding before
any claim consequences. Only the winner creates the cave/owner display and emits
Claimed; later touch or occupancy detections cannot create another context or
hero. The loser can claim another free island normally. Avatar loading stays
asynchronous, shop eligibility updates through IslandId, and existing respawn,
void recovery and PlayerRemoving cleanup remain intact. Stop disconnects the
detector; Start creates fresh references and timing state.

A released island can be claimed by a player already waiting inside it on the
next check. A manually released owner still inside that zone is also eligible
again; move that avatar out when testing deliberate release without re-claiming.
The existing deferred-cleanup regression now does this while retaining all its
stale-hit/cleanup assertions.

Changed files: src/server/Services/IslandService.lua, src/shared/WorldConfig.lua,
tests/phase6b.py, tests/claim_responsiveness.py and this README. All **61** scenarios
pass: the existing 53 plus eight new scenarios for immediate/deduplicated touch,
early/missed-touch recovery within 0.12 simulated seconds, all six rotated walk
entrances, zone bounds and invalid/late/stale character state, occupancy races and
one-island ownership, mixed-path races/release/reuse, live shop eligibility and
respawn/void preservation, and late players/Stop/Start cleanup. Full Luau
compilation, Rojo sourcemap and temporary build/XML source validation pass. These
are real-module tests with deterministic mocks, not Studio physics or wall-clock
network measurements.

### Exact Studio claim responsiveness test

Pull main, run Rojo 7.7.1, sync the entire project and restart the test session.
Keep the normal ownership rules and configured ClaimZones; no debug geometry is
needed. Use Test -> Server & Clients with two clients and watch server Output.

1. Start both players in the Hub without islands or combat.
2. Walk A across a bridge straight into an empty island's UNCLAIMED entrance.
3. Do not jump, circle around or leave/re-enter; keep walking normally or stop
   with the root inside the zone.
4. Expect ownership within roughly 0-0.25 seconds after root entry. Confirm one
   owner portrait/name, cave, Combat context, Knight and Wave 1 enemy. Output
   should show Claim successful via Touched or occupancy fallback. Client
   rendering/network and thumbnail loading can take additional time.
5. Repeat on several of the six islands using fresh sessions: a player already
   owning an island cannot claim another. Inspect ordinary walking on each angle.
6. Have B claim a different island normally. A's combat and owner display must
   stay unchanged. Returning to the Hub shop now enables each owner's offer.
7. Restart so both players are unassigned, then enter the same free zone nearly
   simultaneously.
8. Confirm exactly one owner, cave, portrait and Combat context. The losing
   player remains unassigned and gets no combat/portrait. Remain in the zone to
   test stationary occupancy; repeated touches must not duplicate the winner.
9. Close the winning owner's client. Its portrait/combat/cave disappear.
10. The unassigned remaining player, still inside the freed zone, should claim
    on the next check without another touch. Otherwise walk in normally and
    confirm immediate reuse with the new portrait/name and one fresh context.

Also reset an owner and fall into void; preserve their current context and
return to their owned island. In a fresh session, fall before claiming and
return to the Hub. Confirm an unassigned shopper is still blocked. This claim
fix changed no map/ownership rules and added no saving/offline progress/new heroes.

## Phase 6C.1 — shop, owner portrait and world UI polish

The five Phase 6C.1 changes are retained in Phase 6D:

- Shop opening works before claim, but its UI shows **CLAIM AN ISLAND FIRST**.
  IslandId changes refresh an already open panel. Purchases require the server's
  private IslandService record with the same Player owner; forged replicated
  attributes cannot bypass the check. No gold/ownership changes occur on rejection.
- Each claimed island gets one OwnerAvatar BillboardGui containing a circular
  Roblox headshot and the owner's cave name. Players:GetUserThumbnailAsync uses
  HeadShot / Size180x180 in a separate task. Failed/not-ready requests retain a
  PLAYER placeholder and readable owner name. A late result is accepted only
  for the same owner and same live GUI. Release, leave and world regeneration
  destroy the display; reuse creates the new owner's display. The old UNCLAIMED
  sign is restored on release. Name and portrait share one layout to avoid overlap.
- Generated spawn references were already invisible. Startup now also hides
  existing SpawnLocations near the Hub surface, including their Decals/Textures
  and later-added decals. Hidden legacy spawns retain their enabled state; distant
  unrelated spawns are preserved. The world records HiddenLegacyHubSpawns.
  RespawnLocation assignment and existing void recovery are unchanged.
- HubTitleAnchor is an invisible Attachment on the Hub platform, centered in
  world X/Z, WorldConfig.HubTitleHeight (18 studs) above its top. The centered
  IDLE HERO SIMULATOR · HUB billboard has zero world/local offset and is separate
  from the offset PlayerSpawn and shopkeeper. Only its face rotates toward viewers.
- Every enemy's own HealthDisplay now has WAVE N or WAVE N · BOSS, then its name
  (and boss countdown), HP text and HP bar. Wave data comes from that enemy's
  personal record, not a shared global label. Damage, rewards and deadlines remain
  unchanged. OwnerAvatarHeight (11) and OwnerAvatarMaxDistance (300) are configurable.

Changed files: src/server/Services/{HeroShopService,IslandService,EnemyService}.lua,
src/client/HeroShopPanel.lua, src/shared/WorldConfig.lua, tests/{phase6b,phase6c,
phase6c1}.py, tests/roblox_mock.luau and this README. No balance/config changes,
new heroes, saving, offline rewards or final art were added.

### Exact Phase 6C.1 Studio verification

Pull main, serve with Rojo 7.7.1, sync the **entire** project and restart Play.
Use StudioTesting.Enabled=true, StartingGold=2000, all StartingHeroLevels=1,
and StartingOwnedHeroes={Archer=false,Mage=false} for this test only.

1. Join the Hub; confirm no combat and no visible SpawnLocation plate or decals.
2. Inspect the centered HUB title from several camera angles and distances;
   its anchor must remain over the Hub center, separate from the merchant.
3. Walk to HERO SHOP and open with E without claiming.
4. Confirm CLAIM AN ISLAND FIRST and a disabled purchase button.
5. Try buying; gold and Archer/Mage ownership must remain unchanged.
6. Claim a free island; confirm one cave, Knight and enemy.
7. Immediately inspect WAVE 1, enemy name, HP text and bar above that enemy.
   Wave 1 advances quickly with the normal Knight; repeat a fresh session if missed.
8. Confirm the claimed island shows your Roblox headshot and cave name together.
   If the thumbnail service fails, its fallback must not block claim/combat.
9. Return to the merchant and reopen; the next offer is Archer, cost 100.
10. Buy Archer; subtract exactly 100 from the current balance, allowing natural
    combat income while walking. One Archer appears on your island immediately.
11. Confirm the open shop changes to Mage without resetting combat.
12. Buy Mage for 1000; one Mage appears and the shop shows ALL HEROES UNLOCKED.
13. Watch a normal transition: WAVE 2 (or the current later wave) matches that
    enemy's Wave attribute, and HP/name/bar remain readable.
14. At a boss confirm WAVE 5 · BOSS (or a later boss wave) and the existing
    countdown/HP/bar. A kill or timeout must update the next enemy's wave label.
15. Reset your avatar; respawn on your island with unchanged ownership, portrait,
    combat context and enemy/boss deadline. No duplicate rigs or billboards.
16. Jump into void as an owner; return to your island without combat restart.
    In a fresh session, fall before claim and return to Hub.
17. Start Server & Clients with two players. A and B claim different islands;
    each displays its own name/headshot and has separate combat.
18. Pause B using B's existing Studio debug panel and let A advance; the world
    labels must show their different waves. Resume B; its timer/state stay personal.
19. Close A's client: its portrait/cave/combat disappear and its sign is UNCLAIMED;
    B's portrait, shop state and combat remain intact.
20. Join a new client and claim A's freed island: show the new player's headshot/
    name, one fresh Wave 1 context and no stale portrait. Restore testing defaults,
    sync/restart and verify no Studio debug/RESET HERO controls in production mode.

Also run the single-/two-player combat, claim-race, upgrade, projectile and timeout
checks below. Automated checks cover all 53 scenarios, Luau compilation, Rojo
sourcemap and a temporary Rojo build with XML source validation. They execute
real project modules with mocks, not Roblox Studio: camera rendering, real avatar
thumbnail availability, network replication, prompts and engine physics remain
manual checks. No claim is made that these new visuals were tested in Studio.

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
live character/distance, private island ownership and the next private hero. ProgressionService performs
the same existing cooldown/affordability validation and atomically deducts the
configured price, grants that next hero, publishes stats and emits HeroOwned
with a Player Instance and hero ID. Failed/stale/skipping/out-of-range requests
do not deduct gold. Neither display attributes nor client affordability are trusted.

On success HeroShopService calls HeroService.RefreshOwnedHeroes for the buyer's
existing context. The new rig is added immediately at ArcherSlot/MageSlot using
the same synchronization routine and existing context update connection. Wave,
enemy, boss deadline, Knight and other players stay unchanged. Without an island,
purchases fail with ClaimIslandFirst before any gold deduction or ownership change.
Opening the shop remains allowed and explains the claim requirement. The offer updates in the open shop immediately to Mage or the
all-owned message. Normal Gold HUD also updates from the actual balance.

The old free-choice BuyHero remote/API and BUY HERO branch are removed. Normal
Normal HUD shows compact Gold/Total DPS; owned-hero leveling, bulk modes and
milestone upgrades now open through physical heroes in Phase 6D. Studio debug tools and
testing values remain Studio-gated, with no separate currency or production cheats.

### Exact Phase 6C single-player Studio test

1. In GameConfig set StudioTesting.Enabled=true, StartingGold=2000,
   StartingHeroLevels={Knight=1,Archer=1,Mage=1}, and
   StartingOwnedHeroes={Archer=false,Mage=false}. Pull main, run Rojo, sync the
   **entire** project and restart Play. Required modules are cached per session.
2. Spawn in Hub: no combat. Normal HUD has no permanent hero controls; no Archer/Mage
   purchase buttons/tabs; permanent HUD is Gold/Total DPS only. Confirm the HERO SHOP merchant at the configured
   diagonal Hub position without blocking spawn or a bridge.
3. Walk within 12 studs, use the E prompt. The centered shop opens and offers
   **CLAIM AN ISLAND FIRST**, with the purchase button disabled. No Mage preview
   anywhere in the shop. CLOSE/reopen several times: one GUI, still blocked.
4. Try purchasing before claiming: gold and ownership stay unchanged, and there
   is still no Hub hero/enemy/context. Close and claim Island 1: Knight and a
   Wave 1 enemy spawn. Note its Combat.ContextId, Wave, enemy and Knight.
5. Return to the Hub merchant and open again. Only Archer is offered: damage 8,
   1.43 attacks/s, cost 100. Buy it; exactly 100 is deducted from the current
   balance and one Archer immediately joins that island. The open shop switches
   to Mage (55 damage, 0.42 attacks/s, cost 1K). Double-click must not buy Mage.
6. Return to the merchant while combat continues. Open and buy Mage: gold drops
   by exactly 1000 from its current value (kills may earn gold during walking).
   Mage immediately appears at Island1.MageSlot without resetting enemy, wave,
   boss deadline or Knight. Exactly one Mage rig; its bolts target A's enemy.
7. The same open shop shows ALL HEROES UNLOCKED and no BUY button. CLOSE/reopen:
   merchant remains usable with that message. Owned hero levels/milestones and
   bulk modes work after interacting with each physical hero on your island.
8. Reset the avatar, reopen the shop and confirm session ownership is preserved.
   Repeat from a fresh session with StartingGold=99: Archer BUY is disabled and
   reads CLAIM AN ISLAND FIRST before claim, then NOT ENOUGH GOLD after claim.
   Earn gold; reopen after returning to Hub:
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
pre-claim rejection/respawn, two-client personal UI, GUI/world/player lifecycle,
production gates/original stats and deferred ownership events. No new per-frame
shop loops or remote broadcasts. Full Luau compilation, Rojo sourcemap and a
Rojo build/XML module validation pass.

NPC and shop visuals are prototype Parts/UI. Heroes and prices are unchanged;
there is no Hero 4. Shared HeroConfig metadata is not concealed from exploiters.
Shop UI can stay open after walking away, but buying requires server distance
validation. Progression/ownership remain session-only. Phase 6D is implemented
above; **saving, offline progress and final NPC/UI/map art are not implemented.**

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
**UNCLAIMED** sign. Touched immediately checks the live character's root; a
10 Hz occupancy fallback catches early/missed touches against the same zone.
The first valid claimant wins without yielding. One player can own one
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
hero update. Shop purchases before claim are rejected without progression changes.
Heroes already owned through session progression or Studio configuration spawn at claim.

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

The contextual menu retains selected-owned-hero milestone buttons and
bulk modes x1/x10/x25/x100/MAX/NEXT; permanent hero tabs are removed.
NEXT targets the next configured milestone;
bulk buys sum the increasing rounded per-level costs and may buy a partial
count if funds are insufficient. Unlocking a milestone never buys it automatically.

Purchase remotes accept only IDs/modes and a valid physical-selection token.
The server validates the active owner/instance/selection and payload length/types,
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
   NO ACTIVE COMBAT AREA; pause/reset actions in Hub have no effect. Walk to the
   Hub merchant and press E: CLAIM AN ISLAND FIRST blocks purchases. Claim
   Island 1: Knight spawns. Return to the merchant and buy Archer for 100, then
   Mage for 1000: exactly one rig of each appears at its configured slot.
   Observe arrows/bolts hit only this island's captured enemy.
6. Interact with each physical hero to open its menu; level separately through
   x1/x10/x25/x100/MAX/NEXT and inspect exact
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
5. On A only, open each hero via its physical prompt, level Archer to 50 and buy Quick Draw/Rallying Volley; level Mage
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
`tests/phase6c.py` runs those 38 plus nine shop scenarios.
`tests/phase6c1.py` runs all 47 plus six polish regressions: **53 passed**.
`tests/claim_responsiveness.py` includes all 53 plus eight claim detection
regressions: **61 passed**.
`tests/phase6d.py` includes all 61 plus 13 physical-menu scenarios: **74 passed**.
Earlier shop cases now expect the requested pre-claim rejection; security,
post-claim purchases and lifecycle assertions remain exercised.
Existing progression/security cases are in `tests/progression_regressions.json`.
The mock preserves BindableEvent table copying and now routes FireClient only to
that simulated client's listeners. Run with Python 3 and a Luau CLI:

```sh
LUAU_BIN=/path/to/luau python3 tests/phase6b.py
LUAU_BIN=/path/to/luau python3 tests/phase6c.py
LUAU_BIN=/path/to/luau python3 tests/phase6c1.py
LUAU_BIN=/path/to/luau python3 tests/claim_responsiveness.py
LUAU_BIN=/path/to/luau python3 tests/phase6d.py
LUAU_BIN=/path/to/luau python3 tests/phase6d1.py
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
and the first valid claimant wins. Phase 6D now adds physical upgrade menus above.


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
confirmation for new Phase 6D.1 changes still requires Studio.


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
