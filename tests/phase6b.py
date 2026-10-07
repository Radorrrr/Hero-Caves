"""Run real Luau modules against a deterministic Roblox API mock.
Requires Python 3 and a Luau CLI (LUAU_BIN environment variable or luau on PATH).
This does not verify Studio rendering, physics, replication or network behavior.
"""
from pathlib import Path
import json, os, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
old={'scenarios':json.loads((root/'tests/progression_regressions.json').read_text())}
mock=(root/'tests/roblox_mock.luau').read_text()
modules=[('GameConfig','src/shared/GameConfig.lua'),('EnemyConfig','src/shared/EnemyConfig.lua'),('HeroConfig','src/shared/HeroConfig.lua'),('WorldConfig','src/shared/WorldConfig.lua'),('PlayerDataSchema','src/server/Services/PlayerDataSchema.lua'),('PlayerDataService','src/server/Services/PlayerDataService.lua'),('NumberFormatter','src/shared/NumberFormatter.lua'),('ProgressionMath','src/server/ProgressionMath.lua'),('UpgradeEffects','src/server/UpgradeEffects.lua'),('CombatContexts','src/server/Services/CombatContexts.lua'),('CombatDebugState','src/server/Services/CombatDebugState.lua'),('EnemyService','src/server/Services/EnemyService.lua'),('WaveService','src/server/Services/WaveService.lua'),('EconomyService','src/server/Services/EconomyService.lua'),('ProgressionService','src/server/Services/ProgressionService.lua'),('KnightRig','src/server/Heroes/KnightRig.lua'),('RangedRig','src/server/Heroes/RangedRig.lua'),('CombatService','src/server/Services/CombatService.lua'),('HeroUpgradeService','src/server/Services/HeroUpgradeService.lua'),('HeroService','src/server/Services/HeroService.lua'),('IslandService','src/server/Services/IslandService.lua'),('HeroShopService','src/server/Services/HeroShopService.lua'),('CombatContextService','src/server/Services/CombatContextService.lua'),('CombatDebugService','src/server/Services/CombatDebugService.lua'),('HeroPromptVisibility','src/client/HeroPromptVisibility.lua'),('HeroShopPanel','src/client/HeroShopPanel.lua'),('GoldPopup','src/client/GoldPopup.lua'),('CombatDebugPanel','src/client/CombatDebugPanel.lua')]
common=mock
for name,path in modules:common+=f'modules.{name}=(function()\nlocal script={{Parent=services}}\n'+(root/path).read_text()+'\nend)()\n'
common+='''
modules.GameConfig.DebugLogging=false
local enemies,waves,heroes=modules.EnemyService,modules.WaveService,modules.HeroService
local combat,economy,progression=modules.CombatService,modules.EconomyService,modules.ProgressionService
local mathService=modules.ProgressionMath
local islandService=modules.IslandService
local manager,registry,state=modules.CombatContextService,modules.CombatContexts,modules.CombatDebugState
local hits={}
local originalDamage=combat.DamageEnemy
combat.DamageEnemy=function(hero,target)
 assert(hero.Context==target.Context,'cross-context animation target')
 assert(hero.Model:GetAttribute('AttackPhase')=='Impact')
 assert(hero.Rig.Angle==hero.Config.Animation.ImpactAngle)
 assert((clock-hero.AttackStartedAt)*hero.AnimationSpeed>=hero.Config.Animation.WindupDuration+hero.Config.Animation.SwingDuration)
 if hero.Rig.SetProjectileProgress then
  assert(hero.Rig.Projectile and hero.Rig.ProjectileTarget==target)
  assert((hero.Rig.Projectile.Position-target.Model.PrimaryPart.Position).Magnitude<.001)
  assert(hero.Rig.Projectile:GetAttribute('ContextId')==hero.Context.Id)
  assert(hero.Rig.Projectile:GetAttribute('OwnerUserId')==hero.Owner.UserId)
  assert(hero.Rig.Projectile:GetAttribute('TargetEnemyId')==target.Model:GetAttribute('EnemyId'))
 end
 local hit={At=clock,HeroId=hero.Id,Context=hero.Context,Target=target,Damage=progression.GetHeroDamage(hero.Owner,hero.Id,target.IsBoss)}
 table.insert(hits,hit);hit.Applied=originalDamage(hero,target);return hit.Applied
end
local function character(player)
 local model=Instance.new('Model');model.Name=player.Name;model.Parent=workspace
 local root=Instance.new('Part');root.Name='HumanoidRootPart';root.CFrame=CFrame.new();root.Parent=model
 local hum=Instance.new('Humanoid');hum.Health=100;hum.Parent=model
 player.Character=model;player.CharacterAdded:Fire(model);return model,root,hum
end
local function claim(player,id)
 if not player.Character then character(player) end
 local island=workspace.IdleHeroSimulatorWorld.Islands['Island'..id]
 player.Character:PivotTo(island.Markers.ClaimZone.CFrame)
 island.Markers.ClaimZone.Touched:Fire(player.Character.HumanoidRootPart)
 return manager.GetContext(player)
end
local function active(context,id) return context.HeroesById[id] end
local function contextHits(context,id)
 local list={};for _,hit in hits do if hit.Context==context and (not id or hit.HeroId==id) then table.insert(list,hit) end end;return list
end
local function waitForHits(context,id,count)
 local limit=clock+12
 while #contextHits(context,id)<count do advance(.01);assert(clock<limit,'missing impacts') end
 return contextHits(context,id)
end
local function validateContext(context)
 assert(context.Active and context.Island.Owner==context.Player)
 local seen={}
 for _,hero in heroes.GetActiveHeroes(context) do
  assert(not seen[hero.Id]);seen[hero.Id]=true
  assert(hero.Context==context and hero.Owner==context.Player and hero.Model.Parent==context.HeroFolder)
 end
 assert(#context.EnemyFolder:GetChildren()<=1)
end
local script={Parent={Services=services}}
'''
start=(root/'src/server/main.server.lua').read_text()+'''
local remote=storage.IdleHeroSimulatorRemotes.BuyHeroLevel
local upgradeRemote=storage.IdleHeroSimulatorRemotes.BuyUpgrade
local heroRemote=storage.IdleHeroSimulatorRemotes.PurchaseNextHero
local shop=modules.HeroShopService
local upgrades=modules.HeroUpgradeService
local function interact(player,id)
 local context=manager.GetContext(player)
 local hero=context and active(context,id)
 if not hero then return false end
 if not player.Character then character(player) end
 player.Character:PivotTo(hero.Model.PrimaryPart.CFrame)
 hero.UpgradePrompt.Triggered:Fire(player)
 return player.HeroUpgradeSelection:GetAttribute('Token')
end
local function contextualRequest(event,player,...)
 local args=table.pack(...)
 args.n+=1;args[args.n]=player.HeroUpgradeSelection:GetAttribute('Token')
 event.OnServerEvent:Fire(player,table.unpack(args,1,args.n))
end
local function visitShop(player)
 if not player.Character then character(player) end
 local prompt=islandService.GetHeroShopPrompt()
 player.Character:PivotTo(prompt.Parent.CFrame)
 prompt.Triggered:Fire(player)
end
local function buyNext(player)
 heroRemote.OnServerEvent:Fire(player,player.HeroShop:GetAttribute('OfferToken'))
end
'''
ui='\nmodules.HeroShopPanel.Start()\n;(function()\nlocal previousRuntime=clientRuntime;clientRuntime=true\n;(function()\nlocal script={Parent=services}\n'+(root/'src/client/main.client.lua').read_text()+'\nend)()\nclientRuntime=previousRuntime\nend)()\n'
scenarios={}
# Preserve meaningful unchanged progression/cost/security regression scenarios.
for name in ['milestones','security','bulk-x1','bulk-x10','bulk-x25','bulk-x100','partial-max','next-1','next-10','next-17','next-25','next-72','next-149','next-partial-config','bulk-security','shop-security']:
 before,test=old['scenarios'][name]
 test='local context=claim(p1,1)\n'+test
 if 'OnServerEvent' in test and name!='shop-security':
  # Keep real physical heroes/selection while preventing attacks in formula/security fixtures.
  test=test.replace('heroes.Stop()', 'context.HeroConnection:Disconnect();context.HeroConnection=nil;interact(p1,\'Knight\')')
  test=test.replace('upgradeRemote.OnServerEvent:Fire(p1,', 'contextualRequest(upgradeRemote,p1,')
  test=test.replace('event.OnServerEvent:Fire(p1,', 'contextualRequest(event,p1,')
 test=test.replace('heroes.Stop()','heroes.Stop(context)').replace('heroes.Start()','heroes.Start(context)')
 test=test.replace('enemies.GetActiveEnemy()','enemies.GetActiveEnemy(context)').replace('enemies.Damage(','enemies.Damage(context,').replace('enemies.Spawn(','enemies.Spawn(context,')
 test=test.replace('waves.GetCurrentWave()','waves.GetCurrentWave(context)')
 scenarios['regression-'+name]=(before,test)
scenarios['no-before-claim']=('',ui+r'''
assert(p1.RespawnLocation==workspace.IdleHeroSimulatorWorld.Hub.PlayerSpawn)
assert(not manager.GetContext(p1) and not registry.Get(p1) and not p1:GetAttribute('HasCombatArea'))
assert(p1:GetAttribute('TotalDPS')==0 and progression.GetHeroLevel(p1,'Knight')==1)
assert(alive('Model','Knight')==0 and alive('Model','Slime')==0 and connected()==1)
assert(not workspace:FindFirstChild('IdleHeroSimulatorEnemies') and not workspace:FindFirstChild('IdleHeroSimulatorHeroes'))
advance(35);assert(alive('Model','Knight')==0 and alive('Model','Slime')==0 and economy.GetGold(p1)==0)
assert(p1:GetAttribute('IdleHeroSimulatorWave')==nil)
local context=claim(p1,1);assert(context and context.CurrentWave==1 and #context.Heroes==1)
assert(active(context,'Knight').Model:GetAttribute('OwnerUserId')==101)
assert((active(context,'Knight').Model.PrimaryPart.Position-context.Island.Markers.KnightSlot.Position).Magnitude<.001)
assert((context.CurrentEnemy.Model.PrimaryPart.Position-context.Island.Markers.EnemyPosition.Position).Magnitude<.001)
assert(context.CurrentEnemy.Health==20 and connected()==3)
manager.StartCombat(p1,context.Island);islandService.Claimed:Fire(p1,context.Island.Model);manager.Start()
assert(manager.GetContext(p1)==context and connected()==3 and alive('Model','Knight')==1)
assert(not playerGui.IdleHeroSimulatorProgression.Panel.Visible)
assert(playerGui.IdleHeroSimulatorProgression.TotalDPS.Text=='Total DPS\n'..modules.NumberFormatter.Format(p1:GetAttribute('TotalDPS')))
validateContext(context)
print('PASS: neutral Hub/no combat before claim, marker-driven personal wave1/Knight, no shared folders, active UI/DPS and duplicate-claim/start safety')
''')
scenarios['single-waves-gold']=('',ui+r'''
local context=claim(p1,2)
local event=storage.IdleHeroSimulatorGoldAwarded
advance(.3);assert(context.CurrentEnemy.Health==20 and economy.GetGold(p1)==0)
advance(.2);assert(context.CurrentEnemy==nil and economy.GetGold(p1)==5)
assert(event.Responses[1][1]==p1 and event.Responses[1][2]==5)
assert(playerGui.IdleHeroSimulatorProgression.GoldGain.Text=='+5 Gold')
local limit=clock+10
while context.CurrentWave<3 do advance(.05);assert(clock<limit) end
assert(economy.GetGold(p1)==11 and context.CurrentEnemy.Health==28)
local gold=economy.GetGold(p1);assert(progression.BuyHeroLevels(p1,'Knight','x1'))
assert(economy.GetGold(p1)==gold-10 and progression.GetHeroDamage(p1,'Knight',false)==22)
local deadline=clock+40
while context.CurrentWave<5 do advance(.05);assert(clock<deadline) end
local boss=context.CurrentEnemy;assert(boss.IsBoss and boss.Health==330 and boss.Deadline>clock)
local previous=economy.GetGold(p1)
while context.CurrentEnemy==boss do advance(.01);assert(clock<deadline+30) end
assert(boss.Model.destroyed and economy.GetGold(p1)==previous+44)
assert(event.Responses[#event.Responses][2]==44)
advance(1.2);assert(context.CurrentWave==6)
validateContext(context)
print('PASS: original wave HP/reward growth, real timed damage, owner gold/popups, level damage at impact and personal boss5 victory -> wave6')
''')
allheroes='modules.GameConfig.StudioTesting.Enabled=true\nmodules.GameConfig.StudioTesting.StartingOwnedHeroes={Archer=true,Mage=true}\nmodules.EnemyConfig.BaseHealth=1000000000\n'
scenarios['two-contexts-projectiles']=(allheroes,r'''
economy.SpendGold(p1,economy.GetGold(p1))
local p2=addPlayer(102,'Second');economy.SpendGold(p2,economy.GetGold(p2))
local a=claim(p1,1)
assert(not manager.GetContext(p2) and alive('Model','Knight')==1)
advance(.1);local b=claim(p2,4)
assert(a~=b and a.CurrentEnemy~=b.CurrentEnemy and alive('Model','Knight')==2 and connected()==5)
for _,c in {a,b} do
 validateContext(c)
 for _,id in {'Knight','Archer','Mage'} do
  assert((active(c,id).Model.PrimaryPart.Position-c.Island.Markers[id..'Slot'].Position).Magnitude<.001)
 end
end
assert(not originalDamage(active(a,'Knight'),b.CurrentEnemy))
assert(not originalDamage(active(b,'Mage'),a.CurrentEnemy))
local oldA,oldB=a.CurrentEnemy,b.CurrentEnemy
advance(.2);assert(active(a,'Archer').Rig.Projectile and active(b,'Archer').Rig.Projectile)
local bArrow=active(b,'Archer').Rig.Projectile
local countB=#contextHits(b)
local nextA=enemies.Spawn(a,2,false)
assert(not active(a,'Archer').Rig.Projectile and active(b,'Archer').Rig.Projectile==bArrow)
assert(not originalDamage(active(a,'Archer'),oldA))
local archerA=waitForHits(a,'Archer',3)
local mageA=waitForHits(a,'Mage',2)
local archerB=waitForHits(b,'Archer',3)
local mageB=waitForHits(b,'Mage',2)
assert(math.abs(archerA[3].At-archerA[2].At-.7)<.025)
assert(math.abs(mageA[2].At-mageA[1].At-2.4)<.025)
assert(math.abs(archerB[2].At-archerB[1].At-.7)<.025)
for _,hit in hits do assert(hit.Applied and hit.Target.Context==hit.Context) end
local hpB=b.CurrentEnemy.Health;local goldB=economy.GetGold(p2);countB=#contextHits(b)
assert(enemies.Damage(a,nextA.Health))
assert(economy.GetGold(p1)==6 and economy.GetGold(p2)==goldB and b.CurrentEnemy==oldB and oldB.Health==hpB)
for _,h in a.Heroes do assert(not h.Rig.Projectile and not h.Target) end
advance(1.2)
assert(a.CurrentWave==2 and b.CurrentWave==1 and #contextHits(b)>countB)
validateContext(a);validateContext(b)
print('PASS: two independent crews/enemies/markers, cross-target rejection, projectile owner/hero/target metadata, replacement/death only cancels A and original timing/rewards/waves isolated')
''')
scenarios['independent-bosses']=(allheroes,r'''
local p2=addPlayer(102,'Second');local a=claim(p1,1);local b=claim(p2,4)
heroes.Stop(a);heroes.Stop(b)
economy.SpendGold(p1,economy.GetGold(p1));economy.SpendGold(p2,economy.GetGold(p2))
-- Advance only A to boss5; B remains at personal wave1.
for wave=1,4 do assert(a.CurrentWave==wave);enemies.Damage(a,a.CurrentEnemy.Health);advance(1.05) end
assert(a.CurrentWave==5 and a.CurrentEnemy.IsBoss and b.CurrentWave==1 and not b.CurrentEnemy.IsBoss)
local bossA=a.CurrentEnemy;local gold=economy.GetGold(p1)
for wave=1,4 do enemies.Damage(b,b.CurrentEnemy.Health);advance(1.05) end
assert(b.CurrentWave==5 and b.CurrentEnemy.IsBoss)
local bossB=b.CurrentEnemy
assert(bossB.Deadline-bossA.Deadline>4 and bossB.Model:GetAttribute('TimeRemaining')>bossA.Model:GetAttribute('TimeRemaining'))
bossA.Deadline=clock+.05;local hpB=bossB.Health;local goldB=economy.GetGold(p2)
advance(.1);assert(bossA.Model.destroyed and not a.CurrentEnemy and b.CurrentEnemy==bossB and bossB.Health==hpB)
assert(economy.GetGold(p1)==gold and economy.GetGold(p2)==goldB)
advance(1.05);assert(a.CurrentWave==4 and b.CurrentWave==5)
assert(enemies.Damage(b,bossB.Health));assert(economy.GetGold(p2)==goldB+44 and economy.GetGold(p1)==gold)
advance(1.05);assert(b.CurrentWave==6 and a.CurrentWave==4)
print('PASS: independent wave and boss deadlines, A timeout/no reward -> own previous wave, B unchanged and own boss victory/reward -> wave6')
''')
scenarios['upgrades-personal']=(allheroes+'modules.GameConfig.StudioTesting.StartingHeroLevels={Knight=50,Archer=150,Mage=150}\n',r'''
local p2=addPlayer(102,'Second');local a=claim(p1,1);local b=claim(p2,4)
heroes.Stop(a);heroes.Stop(b)
local bDamage=progression.GetHeroDamage(p2,'Knight',false);local bDPS=p2:GetAttribute('TotalDPS')
for _,pair in {{'Archer','RallyingVolley'},{'Archer','QuickDraw'},{'Archer','GiantSlayer'},{'Mage','EnchantedBlade'},{'Knight','TreasureHunter'},{'Mage','AlchemicalFortune'}} do
 advance(.3);assert(progression.BuyUpgrade(p1,table.unpack(pair)))
 assert(progression.GetHeroDamage(p2,'Knight',false)==bDamage and p2:GetAttribute('TotalDPS')==bDPS)
end
assert(progression.GetGoldMultiplier(p1)==1.5625 and progression.GetGoldMultiplier(p2)==1)
assert(math.abs(progression.GetHeroAttackInterval(p1,'Archer')-.56)<1e-9 and progression.GetHeroAttackInterval(p2,'Archer')==.7)
assert(progression.GetHeroDamage(p1,'Knight',false)==math.floor(20*1.08^49*1.2*1.5+.5))
local d=p1.HeroProgression.Archer:GetAttribute('DPS')
assert(math.abs(d-progression.GetHeroDamage(p1,'Archer',false)/.56)<1e-6)
local sum=0;for _,id in {'Knight','Archer','Mage'} do sum+=p1.HeroProgression[id]:GetAttribute('DPS') end
assert(math.abs(sum-p1:GetAttribute('TotalDPS'))<1e-6)
economy.SpendGold(p1,economy.GetGold(p1));economy.SpendGold(p2,economy.GetGold(p2))
local boss=enemies.Spawn(a,5,true);enemies.Damage(a,boss.Health)
assert(economy.GetGold(p1)==69 and economy.GetGold(p2)==0)
local event=storage.IdleHeroSimulatorGoldAwarded;assert(event.Responses[#event.Responses][1]==p1 and event.Responses[#event.Responses][2]==69)
local p1Normal=progression.GetHeroDamage(p1,'Archer',false)
assert(progression.GetHeroDamage(p1,'Archer',true)==math.floor(8*1.08^149*1.2*2+.5))
assert(progression.ResetHero(p1,'Archer'))
assert(progression.GetHeroLevel(p1,'Archer')==1 and progression.GetHeroLevel(p2,'Archer')==150)
assert(progression.OwnsHero(p1,'Archer') and progression.GetHeroAttackInterval(p1,'Archer')==.7)
assert(progression.GetUpgradeState(p2,'Archer','QuickDraw')=='Available')
print('PASS: local/global/cross/boss/speed/gold modifiers, DPS totals, exact combined gold popup and reset effects remain private to their owner')
''')
scenarios['shop-before-after-claim']=('modules.GameConfig.StudioTesting.Enabled=true\nmodules.GameConfig.StudioTesting.StartingGold=2000\n',ui+r'''
local p2=addPlayer(102,'Second');local b=claim(p2,4)
local panel=playerGui.IdleHeroSimulatorProgression.Panel
assert(not panel.Visible and not panel:FindFirstChild('HeroTabs'))
visitShop(p1);playerGui.IdleHeroSimulatorHeroShop.Panel.Buy.Activated:Fire()
assert(not progression.OwnsHero(p1,'Archer') and not manager.GetContext(p1))
assert(alive('Model','Archer')==0 and economy.GetGold(p1)==2000)
local a=claim(p1,1);visitShop(p1);playerGui.IdleHeroSimulatorHeroShop.Panel.Buy.Activated:Fire()
assert(#a.Heroes==2 and active(a,'Archer') and #b.Heroes==1)
visitShop(p1);advance(.3);playerGui.IdleHeroSimulatorHeroShop.Panel.Buy.Activated:Fire();advance(.01)
assert(progression.OwnsHero(p1,'Mage') and active(a,'Mage') and #a.Heroes==3 and not active(b,'Mage'))
local before=progression.GetHeroLevel(p1,'Archer')
interact(p1,'Archer');advance(.3);panel.LevelUp.Activated:Fire()
assert(progression.GetHeroLevel(p1,'Archer')==before+1 and progression.GetHeroLevel(p2,'Archer')==1)
heroes.Start(a);heroes.Start(b);manager.StartCombat(p1,a.Island);assert(connected()==5)
validateContext(a);validateContext(b)
print('PASS: shop purchases blocked until claim; Archer/Mage buys spawn only on buyer island, unchanged local UI/level request and no duplicate loops')
''')
scenarios['debug-local']=(allheroes+'modules.GameConfig.StudioTesting.StartingHeroLevels={Knight=50,Archer=150,Mage=150}\n',ui+r'''
local remote=storage.IdleHeroSimulatorCombatDebug.Control
local panel=playerGui.IdleHeroSimulatorProgression.CombatDebug
assert(panel.Context.Text:find('NO ACTIVE COMBAT AREA',1,true))
panel.Pause.Activated:Fire();assert(#remote.Requests==0)
remote.OnServerEvent:Fire(p1,'SetPaused',true);assert(not state.IsPaused(p1))
local p2=addPlayer(102,'Second');local a=claim(p1,1);local b=claim(p2,4)
local dataA,dataB=p1.IdleHeroSimulatorCombatDebug,p2.IdleHeroSimulatorCombatDebug
assert(dataA~=dataB and dataA:GetAttribute('Active') and dataB:GetAttribute('Active'))
advance(.2);assert(active(a,'Archer').Rig.Projectile and active(b,'Archer').Rig.Projectile)
local hpB=b.CurrentEnemy.Health;local arrowB=active(b,'Archer').Rig.Projectile
remote.OnServerEvent:Fire(p1,'SetHeroEnabled','Archer',false)
assert(not active(a,'Archer').Rig.Projectile and active(b,'Archer').Rig.Projectile==arrowB)
assert(not dataA.Archer:GetAttribute('AttackEnabled') and dataB.Archer:GetAttribute('AttackEnabled'))
advance(.2);remote.OnServerEvent:Fire(p1,'SetPaused',true)
local aHP=a.CurrentEnemy.Health;local count=#contextHits(a)
advance(2);assert(a.CurrentEnemy.Health==aHP and #contextHits(a)==count and #contextHits(b)>0)
remote.OnServerEvent:Fire(p1,'ResetEnemyHP');assert(a.CurrentEnemy.Health==a.CurrentEnemy.MaxHealth)
local bLevel=progression.GetHeroLevel(p2,'Mage');advance(.2);remote.OnServerEvent:Fire(p1,'ResetHero','Mage')
assert(progression.GetHeroLevel(p1,'Mage')==1 and progression.GetHeroLevel(p2,'Mage')==bLevel)
advance(.2);remote.OnServerEvent:Fire(p1,'SetPaused',false)
advance(.2);remote.OnServerEvent:Fire(p1,'SetHeroEnabled','Archer',true)
advance(1);assert(#contextHits(a)>count and not state.IsPaused(p2))
for _,payload in {{'SetPaused',p2,true},{'ResetEnemyHP',p2},{'ResetHero','Knight',p2},{'SetHeroEnabled','Mage',p2,false},{'SetPaused','true'},{'ResetHero','Unknown'}} do
 advance(.2);remote.OnServerEvent:Fire(p1,table.unpack(payload));assert(not state.IsPaused(p2) and progression.GetHeroLevel(p2,'Mage')==bLevel)
end
assert(dataA:GetAttribute('OwnerUserId')==101 and dataB:GetAttribute('OwnerUserId')==102)
assert(dataA:GetAttribute('TotalDPS')==p1:GetAttribute('TotalDPS') and dataB:GetAttribute('TotalDPS')==p2:GetAttribute('TotalDPS'))
print('PASS: no-context debug UI/actions safe, per-player snapshots and pause/toggles/reset targeting, immediate A projectile cancel, B keeps fighting, malicious target/player payloads rejected')
''')
scenarios['character-cleanup-reclaim']=(allheroes,r'''
local p2=addPlayer(102,'Second');local a=claim(p1,1);local b=claim(p2,4)
advance(.2)
local savedEnemy=a.CurrentEnemy;local wave=a.CurrentWave;local deadline=savedEnemy.Deadline
local savedHeroes=table.clone(a.Heroes);local connections=connected()
local char,root=character(p1)
assert(manager.GetContext(p1)==a and a.CurrentEnemy==savedEnemy and a.CurrentWave==wave and a.CurrentEnemy.Deadline==deadline and connected()==connections)
for _,h in savedHeroes do assert(active(a,h.Id)==h) end
root.CFrame=CFrame.new(0,-100,0);advance(.21)
assert(manager.GetContext(p1)==a and a.CurrentEnemy==savedEnemy and connected()==connections)
local bEnemy=b.CurrentEnemy;local bHeroes=table.clone(b.Heroes);local oldFolder=a.Folder
removePlayer(p1)
assert(not registry.GetStored(p1) and not manager.GetContext(p1) and not a.Active and oldFolder.destroyed)
assert(not a.HeroConnection and not a.WaveConnection and #a.Heroes==0 and #a.HeroConnections==0 and not a.CurrentEnemy)
assert(connected()==3 and manager.GetContext(p2)==b and b.CurrentEnemy==bEnemy)
assert(not islandService.GetIslandOwner(1) and workspace.IdleHeroSimulatorWorld.Islands.Island1.Markers.ClaimZone.OwnershipDisplay.Owner.Text=='UNCLAIMED')
for _,h in savedHeroes do assert(h.Model.destroyed and not h.Rig.Projectile) end
local hitsB=#contextHits(b);advance(1);assert(#contextHits(b)>hitsB)
local p3=addPlayer(103,'Third');local c=claim(p3,1)
assert(c and c.Id~=a.Id and c.CurrentWave==1 and c.Player==p3 and connected()==5)
assert(not originalDamage(savedHeroes[1],c.CurrentEnemy),'old context cannot damage reused island')
local oldC=c.Folder
assert(islandService.ReleaseIsland(p3))
assert(oldC.destroyed and not registry.GetStored(p3) and not p3:GetAttribute('HasCombatArea') and connected()==3)
local nextC=claim(p3,1);assert(nextC and nextC~=c and nextC.CurrentWave==1 and nextC.Id~=c.Id)
removePlayer(p2);removePlayer(p3);assert(connected()==1 and alive('Model','Knight')==0 and alive('Part','Arrow')==0 and alive('Part','MagicBolt')==0)
print('PASS: reset/void keep exact context/wave/enemy/heroes, leaving cancels only owner, remaining combat uninterrupted, island reclaim fresh generation, old hits rejected and reusable release cleanup')
''')
scenarios['boss-respawn-state']=(allheroes,r'''
local context=claim(p1,1);heroes.Stop(context)
for i=1,4 do enemies.Damage(context,context.CurrentEnemy.Health);advance(1.05) end
local boss=context.CurrentEnemy;assert(context.CurrentWave==5 and boss.IsBoss)
local deadline=boss.Deadline;local previousHP=boss.Health
character(p1);assert(manager.GetContext(p1)==context and context.CurrentEnemy==boss and boss.Deadline==deadline and boss.Health==previousHP)
assert(enemies.ResetHealth(context) and boss.Deadline==deadline)
state.SetPaused(p1,true);advance(1)
assert(boss.Deadline==deadline and p1.IdleHeroSimulatorCombatDebug:GetAttribute('BossTimeRemaining')<30)
print('PASS: personal boss persists across avatar reset and HP reset; debug pause does not extend deadline and timer snapshots update by second')
''')
scenarios['production-gates']=('isStudio=false\nmodules.GameConfig.StudioTesting.Enabled=true\nmodules.GameConfig.StudioTesting.StartingOwnedHeroes={Archer=true,Mage=true}\n',ui+r'''
assert(not storage:FindFirstChild('IdleHeroSimulatorCombatDebug') and not p1:FindFirstChild('IdleHeroSimulatorCombatDebug'))
assert(not playerGui.IdleHeroSimulatorProgression:FindFirstChild('CombatDebug'))
assert(economy.GetGold(p1)==0 and progression.GetHeroLevel(p1,'Knight')==1 and not progression.OwnsHero(p1,'Archer'))
local context=claim(p1,1)
assert(not state.SetPaused(p1,true) and not state.SetHeroEnabled(p1,'Knight',false) and not progression.ResetHero(p1,'Knight'))
assert(state.IsHeroEnabled(p1,'Knight'))
advance(.5);assert(economy.GetGold(p1)==5)
print('PASS: production no debug remotes/panels/reset/shortcuts; island combat and personal rewards work')
''')
scenarios['real-speed-boss-isolation']=(allheroes+'modules.GameConfig.StudioTesting.StartingHeroLevels={Knight=1,Archer=150,Mage=150}\n',r"""
local p2=addPlayer(102,'Second');local a=claim(p1,1);local b=claim(p2,4)
heroes.Stop(a);heroes.Stop(b)
for _,pair in {{'Archer','QuickDraw'},{'Archer','RallyingVolley'},{'Archer','GiantSlayer'},{'Mage','EnchantedBlade'}} do
 advance(.3);assert(progression.BuyUpgrade(p1,table.unpack(pair)))
end
local normalB=b.CurrentEnemy
heroes.Start(a);heroes.Start(b)
local ah=waitForHits(a,'Archer',3);local bh=waitForHits(b,'Archer',3)
assert(math.abs(ah[2].At-ah[1].At-.56)<.025 and math.abs(bh[2].At-bh[1].At-.7)<.025)
assert(ah[1].Damage==math.floor(8*1.08^149*1.2+.5) and bh[1].Damage==math.floor(8*1.08^149+.5))
local kh=waitForHits(a,'Knight',1);assert(kh[1].Damage==36)
local kb=waitForHits(b,'Knight',1);assert(kb[1].Damage==20)
local before=#contextHits(a,'Archer')
local boss=enemies.Spawn(a,5,true)
local hitsA=waitForHits(a,'Archer',before+1)
assert(hitsA[#hitsA].Target==boss and hitsA[#hitsA].Damage==math.floor(8*1.08^149*1.2*2+.5))
assert(b.CurrentEnemy==normalB and not b.CurrentEnemy.IsBoss)
assert(math.abs(p1.HeroProgression.Archer:GetAttribute('DPS')-progression.GetHeroDamage(p1,'Archer',false)/.56)<1e-6)
validateContext(a);validateContext(b)
print('PASS: real owner-only global/cross damage and x1.25 attack timeline; B unchanged; A actual boss-only multiplier without inflating normal DPS')
""")
scenarios['six-contexts']= (allheroes,r"""
local playersList={p1};for i=2,6 do playersList[i]=addPlayer(100+i,'Player'..i) end
local contexts={}
for i,player in playersList do contexts[i]=claim(player,i);assert(contexts[i] and #contexts[i].Heroes==3) end
assert(connected()==13 and alive('Model','Knight')==6 and alive('Model','Archer')==6 and alive('Model','Mage')==6)
advance(4)
for _,context in contexts do
 validateContext(context)
 for _,hit in contextHits(context) do assert(hit.Target.Context==context and hit.Applied) end
 for _,id in {'Knight','Archer','Mage'} do assert(#contextHits(context,id)>=2) end
end
local seventh=addPlayer(107,'Seventh');character(seventh)
assert(not manager.GetContext(seventh))
claim(seventh,1);assert(not manager.GetContext(seventh))
local retained=contexts[4].CurrentEnemy
removePlayer(playersList[2]);assert(connected()==11 and contexts[4].CurrentEnemy==retained)
local new=claim(seventh,2);assert(new and #new.Heroes==3 and connected()==13)
manager.Stop();assert(connected()==1 and alive('Model','Knight')==0 and alive('Part','Arrow')==0 and next(registry.GetAll())==nil)
manager.Start();assert(connected()==13 and alive('Model','Knight')==6)
for _,player in players:GetPlayers() do removePlayer(player) end
assert(connected()==1 and next(registry.GetAll())==nil and alive('Model','Slime')==0)
print('PASS: six simultaneous full crews/contexts, independent references under load, seventh blocked, one departure/reclaim isolated and all-context Stop/Start/leave cleanup')
""")
scenarios['claim-race-contexts']=('',r"""
local p2=addPlayer(102,'Second');character(p1);character(p2)
local zone=workspace.IdleHeroSimulatorWorld.Islands.Island1.Markers.ClaimZone
p1.Character:PivotTo(zone.CFrame);p2.Character:PivotTo(zone.CFrame)
zone.Touched:Fire(p1.Character.HumanoidRootPart);zone.Touched:Fire(p2.Character.HumanoidRootPart)
assert(manager.GetContext(p1) and not manager.GetContext(p2) and alive('Model','Knight')==1)
local context=manager.GetContext(p1)
assert(manager.StartCombat(p2,context.Island)==nil)
assert(connected()==3)
for i=1,10 do islandService.Claimed:Fire(p1,context.Island.Model) end
assert(connected()==3 and manager.GetContext(p1)==context and alive('Model','Knight')==1)
print('PASS: competing claim creates one context only, no forged island-owner startup and duplicate claim notifications idempotent')
""")
scenarios['exact-cap-double-reward']=('',ui+r"""
local p2=addPlayer(102,'Second');local context=claim(p1,1);heroes.Stop(context)
local death=context.CurrentEnemy
assert(enemies.Damage(context,death.Health))
local event=storage.IdleHeroSimulatorGoldAwarded
assert(economy.GetGold(p1)==5 and economy.GetGold(p2)==0 and event.Responses[#event.Responses][2]==5)
enemies.Defeated:Fire(p1,context.Id,death.Sequence);assert(economy.GetGold(p1)==5 and #event.Responses==1)
economy.AddGold(p1,modules.GameConfig.Economy.MaxGold-7)
local boss=enemies.Spawn(context,5,true);assert(enemies.Damage(context,boss.Health))
assert(economy.GetGold(p1)==modules.GameConfig.Economy.MaxGold and economy.GetGold(p2)==0)
assert(event.Responses[#event.Responses][2]==2)
local count=#event.Responses
local normal=enemies.Spawn(context,6,false);enemies.Damage(context,normal.Health)
assert(#event.Responses==count,'no positive delta at cap means no popup')
print('PASS: death signal duplicate rejection, only owner rewards, exact capped actual reward popup and no rewards to unclaimed players')
""")
scenarios['long-frame-stale']= (allheroes,r"""
local p2=addPlayer(102,'Second');local a=claim(p1,1);local b=claim(p2,4)
tick(.01);assert(#hits==0)
tick(1.5);assert(#contextHits(a)==3 and #contextHits(b)==3)
for _,hit in hits do assert(hit.Applied) end
tick(.01);assert(#contextHits(a)==3 and #contextHits(b)==3,'no catch-up hits')
local old=a.CurrentEnemy;local oldHero=active(a,'Archer')
local replacement=enemies.Spawn(a,2,false)
assert(not originalDamage(oldHero,old) and not originalDamage(oldHero,b.CurrentEnemy))
advance(1);assert(#contextHits(a)>3 and #contextHits(b)>3)
for _,hit in contextHits(a) do assert(hit.Target==old or hit.Target==replacement) end
print('PASS: long frames issue at most one impact per hero per context, no catch-up duplicate, stale/replaced and foreign targets rejected')
""")
scenarios['studio-disabled']=('',ui+r"""
assert(isStudio and not modules.GameConfig.StudioTesting.Enabled)
assert(not storage:FindFirstChild('IdleHeroSimulatorCombatDebug') and not p1:FindFirstChild('IdleHeroSimulatorCombatDebug'))
local context=claim(p1,1)
assert(not state.SetPaused(p1,true) and not progression.ResetHero(p1,'Knight'))
advance(.5);assert(economy.GetGold(p1)==5)
print('PASS: Studio without testing flag has no debug tools/reset, normal personal combat unaffected')
""")

scenarios['global-floor-removal']=("local function oldFloor(name,size,position,parent)\n local obj=Instance.new('Part');obj.Name=name;obj.Size=size;obj.CFrame=CFrame.new(position)\n obj.Anchored=true;obj.CanCollide=true;obj.Transparency=0;obj.Parent=parent or workspace;return obj\nend\n\nlocal base=oldFloor('Baseplate',Vector3.new(512,4,512),Vector3.new(0,-2,0))\nlocal nested=Instance.new('Model');nested.Name='LegacyMap';nested.Parent=workspace\nlocal wide=oldFloor('OldLargeSlab',Vector3.new(300,5,300),Vector3.new(0,-12,0),nested)\nlocal named=oldFloor('Floor',Vector3.new(100,4,100),Vector3.new(0,-2,0))\nlocal small=oldFloor('SmallProp',Vector3.new(4,4,4),Vector3.new(20,1,0))\nlocal wall=oldFloor('Wall',Vector3.new(200,100,200),Vector3.new(0,50,0))\nlocal far=oldFloor('UnrelatedFloor',Vector3.new(512,4,512),Vector3.new(5000,-2,0))\n","\nassert(base.destroyed and wide.destroyed and named.destroyed)\nassert(not small.destroyed and not wall.destroyed and not far.destroyed)\nlocal world=workspace.IdleHeroSimulatorWorld\nassert(world:GetAttribute('RemovedGlobalFloorCount')==3)\nassert(#world.Islands:GetChildren()==6 and #world.Bridges:GetChildren()==6)\nfor _,obj in world:GetDescendants() do\n if obj:IsA('BasePart') then\n  assert(obj.Size.X<128 and obj.Size.Z<128,'no generated global slab')\n end\nend\nassert(not workspace:FindFirstChild('Baseplate'))\nassert(islandService.RemoveGlobalFloors()==0,'generated Hub/islands/bridges must not be removed')\nfor i=1,6 do\n local b=world.Bridges['Bridge'..i];local p=world.Islands['Island'..i].Platform\n assert(b.Transparency==0 and b.CanCollide and b.CastShadow)\n assert(p.Transparency==0 and p.CanCollide and p.Size.Y==4)\nend\nassert(world.Hub.Platform.Transparency==0 and world.Hub.Platform.CanCollide and world.Hub.Platform.Size.Y==4)\nprint('PASS: removes old Baseplate, named floor and nested broad slab; no generated global floor, preserves props/vertical/far geometry, seven solid platforms and six opaque colliding bridges')\n")

scenarios['hidden-marker-textures']=('',"\nlocal world=workspace.IdleHeroSimulatorWorld\nlocal function hidden(obj)\n assert(obj.Transparency==1 and not obj.CastShadow and not obj.CanCollide)\n for _,d in obj:GetDescendants() do if d:IsA('Decal') or d:IsA('Texture') then assert(d.Transparency==1) end end\nend\nhidden(world.Hub.PlayerSpawn)\nassert(world.Hub.PlayerSpawn.SpawnTexture.Transparency==1)\nfor i=1,6 do\n local island=world.Islands['Island'..i]\n for _,m in island.Markers:GetChildren() do hidden(m) end\n assert(island.Markers.ClaimZone.CanTouch and island.Markers.ClaimZone.OwnershipDisplay.Owner.Text=='UNCLAIMED')\n assert(island.Markers.PlayerSpawn.Enabled and island.Markers.PlayerSpawn.SpawnTexture.Transparency==1)\nend\ncharacter(p1);claim(p1,6);assert(islandService.GetIslandOwner(6)==p1)\nlocal c,r=character(p1)\nassert((r.Position-(world.Islands.Island6.Markers.PlayerSpawn.Position+Vector3.new(0,3,0))).Magnitude<.001)\nprint('PASS: invisible technical parts, no spawn decals/marker textures, visible ownership sign, touch claiming and reference spawn remain functional')\n")

scenarios['deferred-lifecycle']=('',r"""
local a=claim(p1,1);local p2=addPlayer(102,'Second');local b=claim(p2,4)
local oldHero,oldEnemy=active(a,'Knight'),a.CurrentEnemy
local queue={}
for _,obj in objects do
 if obj.ClassName=='BindableEvent' then
  obj.Event.Fire=function(self,...)
   local args=table.pack(...)
   for _,connection in self.Listeners do
    if connection.connected then table.insert(queue,function()
     if connection.connected then connection.fn(table.unpack(args,1,args.n)) end
    end) end
   end
  end
 end
end
local function flush()
 local count=0
 while #queue>0 do count+=1;assert(count<1000);table.remove(queue,1)() end
end
islandService.ReleaseIsland(p1)
-- Leave the detection area so the new occupancy fallback cannot intentionally re-claim.
p1.Character:PivotTo(workspace.IdleHeroSimulatorWorld.Hub.PlayerSpawn.CFrame)
assert(not registry.IsActive(a) and not manager.GetContext(p1))
assert(not originalDamage(oldHero,oldEnemy))
advance(.1);assert(#contextHits(a)==0,'released context cannot attack before deferred cleanup')
flush();assert(not a.Active and a.Folder==nil and manager.GetContext(p2)==b)
local fresh=claim(p1,1);assert(not fresh);flush();fresh=manager.GetContext(p1)
assert(fresh and fresh~=a and fresh.Id~=a.Id)
local freshHero,freshEnemy=active(fresh,'Knight'),fresh.CurrentEnemy
islandService.ReleaseIsland(p1);claim(p1,1);flush()
local nextContext=manager.GetContext(p1)
assert(nextContext and nextContext~=fresh and nextContext.CurrentWave==1)
assert(not originalDamage(freshHero,freshEnemy) and manager.GetContext(p2)==b)
players.PlayerRemoving:Fire(p1);p1.Parent=nil;advance(.1);flush()
assert(not registry.GetStored(p1) and manager.GetContext(p2)==b)
validateContext(b)
print('PASS: deferred claim/release/reclaim/departure callbacks; inactive ownership blocks stale hits before cleanup; other context preserved')
""")

scenarios['bindable-claim-runtime-integration']=('',ui+r"""
-- Demonstrate Roblox argument semantics before driving the real Touched path.
local probe=Instance.new('BindableEvent')
local original={Model=workspace.IdleHeroSimulatorWorld.Islands.Island1,Player=p1,Nested={Value=7}}
local received
probe.Event:Connect(function(value) received=value end)
probe:Fire(original)
assert(received~=original and received.Nested~=original.Nested)
assert(received.Model==original.Model and received.Player==p1)
local payloads={}
islandService.Claimed:Connect(function(player,model)
 assert(model.ClassName=='Model','claim event must not send a copied ownership table')
 table.insert(payloads,{Player=player,Model=model})
end)
local a=claim(p1,1)
assert(a and a.Island==islandService.GetIsland(p1) and a.Island.Model==original.Model)
assert(a.CurrentWave==1 and a.CurrentEnemy and active(a,'Knight'))
assert(p1:GetAttribute('HasCombatArea') and math.abs(p1:GetAttribute('TotalDPS')-20/1.3)<1e-8)
assert(not playerGui.IdleHeroSimulatorProgression.Panel.Visible and p1:GetAttribute('HasCombatArea'))
local p2=addPlayer(102,'Second');assert(not manager.GetContext(p2) and p2:GetAttribute('TotalDPS')==0)
local b=claim(p2,2)
assert(b and b.Island==islandService.GetIsland(p2) and b~=a and b.CurrentWave==1)
assert(#payloads==2 and payloads[1].Player==p1 and payloads[2].Player==p2)
validateContext(a);validateContext(b)
waitForHits(a,'Knight',1);waitForHits(b,'Knight',1)
assert(economy.GetGold(p1)==5 and economy.GetGold(p2)==5)
print('PASS: Roblox table copying demonstrated; actual Touched -> BindableEvent -> authoritative lookup -> context/wave/enemy/Knight -> active client UI/DPS for two players')
""")
scenarios['stable-enemy-event-handles']=(allheroes+'modules.GameConfig.StudioTesting.StartingGold=0\n',r"""
local a=claim(p1,1);local p2=addPlayer(102,'Second');local b=claim(p2,2)
local notices,deaths={},{}
enemies.Changed:Connect(function(player,id)
 assert(player.ClassName=='Player' and type(id)=='string');table.insert(notices,{player,id})
end)
enemies.Defeated:Connect(function(player,id,sequence)
 assert(player.ClassName=='Player' and type(id)=='string' and type(sequence)=='number')
 table.insert(deaths,{player,id,sequence})
end)
local oldEnemy=a.CurrentEnemy
advance(.35);assert(active(a,'Archer').Rig.Projectile)
local replacement=enemies.Spawn(a,2,false)
assert(not active(a,'Archer').Rig.Projectile and b.CurrentEnemy~=replacement)
assert(not originalDamage(active(a,'Knight'),oldEnemy))
heroes.Stop(a);enemies.Damage(a,replacement.Health)
assert(#deaths==1 and deaths[1][1]==p1 and economy.GetGold(p1)==6 and economy.GetGold(p2)==0)
enemies.Defeated:Fire(p1,a.Id,replacement.Sequence)
enemies.Defeated:Fire(p2,b.Id,12345)
assert(economy.GetGold(p1)==6 and economy.GetGold(p2)==0 and next(a.PendingRewards)==nil)
local oldId=a.Id;islandService.ReleaseIsland(p1);local fresh=claim(p1,1)
enemies.Defeated:Fire(p1,oldId,replacement.Sequence)
assert(economy.GetGold(p1)==6 and fresh.Id~=oldId and manager.GetContext(p2)==b)
print('PASS: enemy notifications use Player/IDs; replacement cancels own projectiles; private one-shot reward claims reject duplicate, unknown and released generations')
""")
scenarios['startup-reconciliation-and-diagnostics']=('',r"""
local context=claim(p1,1);local island=context.Island
manager.Stop();assert(not manager.GetContext(p1) and connected()==1)
local marker=island.Markers.KnightSlot;local parent=marker.Parent;marker.Parent=nil
local warningCount=#warnings
assert(not manager.StartCombat(p1,island) and #warnings==warningCount+1)
assert(warnings[#warnings]:find('missing/invalid runtime marker KnightSlot',1,true))
assert(not p1:GetAttribute('HasCombatArea') and p1:GetAttribute('TotalDPS')==0)
marker.Parent=parent
local startWave=waves.Start
waves.Start=function() error('injected startup failure') end
assert(not manager.StartCombat(p1,island))
assert(warnings[#warnings]:find('injected startup failure',1,true))
assert(not registry.GetStored(p1) and not island.Model:FindFirstChild('Combat'))
assert(not p1:GetAttribute('HasCombatArea') and connected()==1)
waves.Start=startWave
manager.Start();local fresh=manager.GetContext(p1)
assert(fresh and fresh.CurrentWave==1 and fresh.Island==island and #fresh.Heroes==1)
manager.Start();assert(connected()==3 and alive('Model','Knight')==1)
local count=#warnings;isStudio=false
assert(not manager.StartCombat(p1,nil) and #warnings==count,'diagnostics must be Studio-only')
print('PASS: startup marker validation/error diagnostics, rollback clears active state, existing ownership reconciliation and idempotent listener initialization; production diagnostics silent')
""")

def run_scenarios(selected):
 test_directory=tempfile.mkdtemp(prefix="idle-hero-simulator-phase6b-")
 failed=[]
 for name,(before,test) in selected.items():
  path=Path(test_directory)/('idle-hero-simulator-phase6b-'+name+'.luau');path.write_text(common+before+'\n'+start+test)
  proc=subprocess.run([os.environ.get('LUAU_BIN','luau'),str(path)],capture_output=True,text=True)
  print(name,proc.returncode,proc.stdout.strip(),proc.stderr.strip())
  if proc.returncode:failed.append(name)
 print('SCENARIOS',len(selected),'FAILED',failed);assert not failed,failed

if __name__ == "__main__":
 run_scenarios(scenarios)
