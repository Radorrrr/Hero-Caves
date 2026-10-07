"""Phase 7 real service regressions with an isolated, injectable DataStore mock."""
from phase6d1 import scenarios, run_scenarios
from phase6b import allheroes, ui
scenarios=scenarios.copy()
persistent='modules.GameConfig.Persistence.StudioMode="DataStore"\n'
helpers=r'''
local data,schema=modules.PlayerDataService,modules.PlayerDataSchema
local namespace=modules.GameConfig.Persistence.StudioDataStoreName
local function saved(player) return storeDB[namespace]['Player_'..player.UserId] end
'''
rich=persistent+r'''
local ns=modules.GameConfig.Persistence.StudioDataStoreName
storeDB[ns]={Player_101={SchemaVersion=1,Gold=12345,Wave=27,Heroes={
 Knight={Owned=true,Level=50,PurchasedUpgrades={'SharpenedBlade'}},
 Archer={Owned=true,Level=18,PurchasedUpgrades={}},Mage={Owned=false,Level=1,PurchasedUpgrades={}}}}}
'''
scenarios['persistence-rich-load-leave-rejoin']=(rich,helpers+r'''
assert(p1:GetAttribute('DataReady') and not manager.GetContext(p1))
assert(economy.GetGold(p1)==12345 and progression.GetHeroLevel(p1,'Knight')==50)
assert(progression.GetHeroLevel(p1,'Archer')==18 and progression.GetNextHero(p1)=='Mage')
assert(progression.GetUpgradeState(p1,'Knight','SharpenedBlade')=='Purchased')
local damage=progression.GetHeroDamage(p1,'Knight',false)
local c=claim(p1,1);assert(c.CurrentWave==27 and active(c,'Archer') and not active(c,'Mage'))
assert(c.CurrentEnemy.Health==c.CurrentEnemy.MaxHealth)
local old=p1;removePlayer(old)
local record=saved(old);assert(record.Gold==12345 and record.Wave==27 and not record.Session)
for key in record do assert(key=='SchemaVersion' or key=='Gold' or key=='Wave' or key=='Heroes') end
for _,hero in record.Heroes do for key in hero do assert(key=='Owned' or key=='Level' or key=='PurchasedUpgrades') end end
local fresh=addPlayer(101,'Rejoined');local next=claim(fresh,4)
assert(economy.GetGold(fresh)==12345 and next.CurrentWave==27)
assert(progression.GetHeroDamage(fresh,'Knight',false)==damage and active(next,'Archer'))
assert(next~=c and c.CurrentEnemy==nil and not c.Active)
print('PASS: exact 12345/W27/K50/A18/M-unowned/milestone roundtrip, fresh island/combat and derived stats')
''')
scenarios['persistence-defaults-and-migration']=(persistent,helpers+r'''
assert(economy.GetGold(p1)==0 and data.GetWave(p1)==1)
assert(progression.OwnsHero(p1,'Knight') and not progression.OwnsHero(p1,'Archer'))
local migrated=schema.Reconcile({Gold=-50,Wave=0,Heroes={Knight={Owned=false,Level=50.9,Upgrades={SharpenedBlade=true,Unknown=true}},Archer={Owned=true,Level=999999},Mage={Owned=false,Level=99,PurchasedUpgrades={'MysticPower'}}}})
assert(migrated.SchemaVersion==1 and migrated.Gold==0 and migrated.Wave==1)
assert(migrated.Heroes.Knight.Owned and migrated.Heroes.Knight.Level==50 and migrated.Heroes.Knight.Upgrades.SharpenedBlade)
assert(not migrated.Heroes.Knight.Upgrades.Unknown and migrated.Heroes.Archer.Level==modules.HeroConfig.Archer.MaxLevel)
assert(migrated.Heroes.Mage.Level==1 and not next(migrated.Heroes.Mage.Upgrades))
local malformed=schema.Reconcile({Gold=0/0,Wave=math.huge,Heroes=false})
assert(malformed.Gold==0 and malformed.Wave==1 and malformed.Heroes.Knight.Level==1)
local duplicates=schema.Reconcile({Heroes={Knight={Level=50,PurchasedUpgrades={'SharpenedBlade','SharpenedBlade','Unknown'}}}})
assert(#schema.Encode(duplicates).Heroes.Knight.PurchasedUpgrades==1)
assert(not schema.Reconcile({SchemaVersion=2}) and not schema.Reconcile('corrupt'))
print('PASS: normal defaults; partial/legacy reconciliation, finite bounds, ownership/upgrade allowlist and future-schema rejection')
''')
for reason,seed in [('future','{SchemaVersion=2,Gold=987}'),('root','"corrupt"'),('locked','{SchemaVersion=1,Gold=987,Session={Token="foreign",Expires=1700000999}}')]:
 scenarios['persistence-load-reject-'+reason]=(persistent+f'local ns=modules.GameConfig.Persistence.StudioDataStoreName;storeDB[ns]={{Player_101={seed}}}\n',helpers+r'''
assert(not data.IsReady(p1) and p1.KickReason)
assert(not claim(p1,1) and not economy.AddGold(p1,100) and not progression.PurchaseNextHero(p1))
assert(not data.Save(p1,true) and #storeCalls==1)
assert(saved(p1)~=nil)
print('PASS: unsafe load rejected, no claim/mutation/save/default overwrite')
''')
scenarios['persistence-load-failure-no-overwrite']=(rich+'storeFailures=10\n',helpers+r'''
assert(#storeCalls==3 and not data.IsReady(p1) and p1.KickReason)
assert(saved(p1).Gold==12345 and not saved(p1).Session)
removePlayer(p1);assert(not data.GetProfile(p1) and #storeCalls==3)
print('PASS: bounded three load failures retain existing record; no defaults and no leave save')
''')
scenarios['persistence-load-retries']=(persistent+'storeFailures=2\n',helpers+r'''
assert(data.IsReady(p1) and #storeCalls==3 and economy.GetGold(p1)==0)
print('PASS: transient load retries recover safely')
''')
scenarios['persistence-save-retry-and-dirty']=(persistent,helpers+r'''
economy.AddGold(p1,123);local profile=data.GetProfile(p1);storeFailures=3
local n=#storeCalls;assert(not data.Save(p1,false) and #storeCalls==n+3)
assert(profile.SavedRevision<profile.Revision and saved(p1).Gold==0)
assert(data.Save(p1,false) and saved(p1).Gold==123 and profile.SavedRevision==profile.Revision)
print('PASS: failed saves retain dirty memory and last durable record; subsequent UpdateAsync succeeds')
''')
scenarios['persistence-concurrent-save-snapshot']=(persistent,helpers+r'''
economy.AddGold(p1,10);local profile=data.GetProfile(p1);local n=#storeCalls
storeHook=function() storeHook=nil;economy.AddGold(p1,20);local ok,why=data.Save(p1,false);assert(not ok and why=='Busy') end
assert(data.Save(p1,false) and #storeCalls==n+1 and saved(p1).Gold==10)
assert(economy.GetGold(p1)==30 and profile.Revision>profile.SavedRevision)
assert(data.Save(p1,false) and saved(p1).Gold==30)
print('PASS: immutable in-flight snapshot, per-profile save serialization and revision-safe dirty tracking')
''')
scenarios['persistence-leave-during-save']=(persistent,helpers+r'''
economy.AddGold(p1,10);local n=#storeCalls
storeHook=function() storeHook=nil;economy.AddGold(p1,20);removePlayer(p1) end
assert(data.Save(p1,false) and #storeCalls==n+2)
assert(saved(p1).Gold==30 and not saved(p1).Session and not data.GetProfile(p1))
print('PASS: leave during autosave queues final current snapshot and session release before cleanup')
''')
scenarios['persistence-session-loss']=(persistent,helpers+r'''
economy.AddGold(p1,10);saved(p1).Session.Token='new-owner'
assert(not data.Save(p1,false) and p1.KickReason and not data.IsReady(p1))
assert(saved(p1).Gold==0 and saved(p1).Session.Token=='new-owner')
print('PASS: stale session cannot overwrite newer owner and is removed from gameplay')
''')
scenarios['persistence-autosave-lease-shutdown']=(persistent,helpers+r'''
local profile=data.GetProfile(p1);local n=#storeCalls;advance(110)
assert(#storeCalls==n,'clean profile skips unnecessary data writes before lease renewal')
advance(110);assert(#storeCalls==n+1 and saved(p1).Session.Expires>1700000300)
economy.AddGold(p1,222);advance(110);assert(saved(p1).Gold==222 and profile.Revision==profile.SavedRevision)
local p2=addPlayer(102,'Second');economy.AddGold(p2,333)
for _,close in shutdownCallbacks do close() end
assert(saved(p1).Gold==222 and not saved(p1).Session and saved(p2).Gold==333 and not saved(p2).Session)
assert(not data.GetProfile(p1) and not data.GetProfile(p2))
print('PASS: staggered autosave, clean lease renewal and independent concurrent shutdown releases')
''')
scenarios['persistence-pending-wave-and-boss-restore']=(persistent,helpers+r'''
local c=claim(p1,1);enemies.Remove(c);advance(.01)
assert(c.PendingWave==2 and data.GetWave(p1)==2)
data.Save(p1,false);assert(saved(p1).Wave==2)
local island=c.Island;manager.StopCombat(p1);data.SetWave(p1,5);manager.StartCombat(p1,island);c=manager.GetContext(p1)
assert(c.CurrentWave==5 and c.CurrentEnemy.IsBoss and c.CurrentEnemy.Health==c.CurrentEnemy.MaxHealth)
assert(math.abs(c.CurrentEnemy.Deadline-time()-modules.GameConfig.BossTimeLimit)<.01)
c.CurrentEnemy.Deadline=time();advance(.01);assert(c.PendingWave==4 and data.GetWave(p1)==4)
removePlayer(p1);assert(saved(p1).Wave==4)
print('PASS: resolved advance/boss rollback persist during delay; restored boss has fresh HP and full timer')
''')
scenarios['persistence-loading-blocks-gameplay']=(persistent+r'''
local spawn=task.spawn;local queued={}
task.spawn=function(fn,...) local args=table.pack(...);table.insert(queued,function() fn(table.unpack(args,1,args.n)) end) end
''',helpers+r'''
assert(not p1:GetAttribute('DataReady') and not claim(p1,1))
assert(not economy.AddGold(p1,500) and not progression.PurchaseNextHero(p1))
task.spawn=spawn;for _,job in queued do job() end
assert(data.IsReady(p1) and p1.HeroProgression and economy.GetGold(p1)==0)
assert(claim(p1,1).CurrentWave==1)
print('PASS: deferred load prevents all gameplay; synchronous initialization precedes successful claim')
''')
scenarios['persistence-studio-presets-do-not-overwrite']=(rich+r'''
modules.GameConfig.StudioTesting.Enabled=true
local debugNS=modules.GameConfig.Persistence.StudioDebugDataStoreName
storeDB[debugNS]=clone(storeDB[modules.GameConfig.Persistence.StudioDataStoreName])
modules.GameConfig.StudioTesting.StartingGold=999999
modules.GameConfig.StudioTesting.StartingHeroLevels.Knight=99
''',helpers+r'''
assert(economy.GetGold(p1)==12345 and progression.GetHeroLevel(p1,'Knight')==50)
assert(storeCalls[1].Namespace==modules.GameConfig.Persistence.StudioDebugDataStoreName)
assert(not storeDB[modules.GameConfig.Persistence.DataStoreName])
print('PASS: Studio debug namespace isolated; existing loaded values survive starting presets')
''')
scenarios['persistence-production-ignores-debug']=(persistent+r'''
isStudio=false;modules.GameConfig.StudioTesting.Enabled=true
''',helpers+r'''
assert(storeCalls[1].Namespace==modules.GameConfig.Persistence.DataStoreName)
assert(economy.GetGold(p1)==0 and progression.GetHeroLevel(p1,'Knight')==1)
local _,_,hum=character(p1);assert(hum.WalkSpeed==16 and not storage.IdleHeroSimulatorCombatDebug)
print('PASS: production uses only production store, ignores test seeds/speed and exposes no debug remote')
''')
scenarios['studio-speed-respawn-and-reset-isolation']=(persistent+r'''
modules.GameConfig.StudioTesting.Enabled=true
modules.GameConfig.StudioTesting.StartingGold=10000
''',helpers+r'''
local a=claim(p1,1);assert(p1.Character:FindFirstChildOfClass('Humanoid').WalkSpeed==32)
local _,_,hum=character(p1);assert(hum.WalkSpeed==32)
local p2=addPlayer(102,'Second');local b=claim(p2,4)
waves.Stop(a);data.SetWave(p1,20);waves.Start(a)
waves.Stop(b);data.SetWave(p2,12);waves.Start(b)
local old=a.CurrentEnemy;local other=b.CurrentEnemy;local rig=active(a,'Knight').Model
local connection=a.WaveConnection;local gold=economy.GetGold(p1);local level=progression.GetHeroLevel(p1,'Knight')
a.PendingWave=21;a.NextSpawnAt=time()+1;table.insert(a.PendingRewards,{Amount=999})
storage.IdleHeroSimulatorCombatDebug.Control.OnServerEvent:Fire(p1,'ResetWave')
assert(a.CurrentWave==1 and data.GetWave(p1)==1 and not a.PendingWave and #a.PendingRewards==0)
assert(old~=a.CurrentEnemy and a.CurrentEnemy.Health==a.CurrentEnemy.MaxHealth)
assert(a.WaveConnection==connection and active(a,'Knight').Model==rig)
assert(economy.GetGold(p1)==gold and progression.GetHeroLevel(p1,'Knight')==level)
assert(b.CurrentWave==12 and b.CurrentEnemy==other and data.GetWave(p2)==12)
assert(data.Save(p1,false))
local ns=modules.GameConfig.Persistence.StudioDebugDataStoreName
assert(storeDB[ns].Player_101.Wave==1 and not storeDB[modules.GameConfig.Persistence.DataStoreName])
advance(.3);assert(a.CurrentWave==1,'old queued transition cannot fire after reset')
print('PASS: speed reapplies on respawn; reset cancels old boss/transition/rewards, preserves progression/context, isolates B and saves wave1 only in test namespace')
''')
for value in ['false','nil']:
 scenarios['studio-speed-normal-'+value]=('modules.GameConfig.StudioTesting.Enabled=true;modules.GameConfig.StudioTesting.PlayerWalkSpeed='+value, r'''
local _,_,hum=character(p1);assert(hum.WalkSpeed==16)
print('PASS: unset/false Studio speed preserves normal humanoid behavior')
''')

scenarios['persistence-leave-during-load']=(persistent,helpers+r"""
storeHook=function(_,key) if key=='Player_102' then storeHook=nil;for _,p in players:GetPlayers() do if p.UserId==102 then removePlayer(p) end end end end
local p2=addPlayer(102,'LeavingWhileLoading')
assert(not data.GetProfile(p2) and not saved(p2).Session and not p2:GetAttribute('DataReady'))
assert(not manager.GetContext(p2) and not p2.HeroProgression)
print('PASS: leave during load releases acquired lease without publishing gameplay/default overwrite')
""")
scenarios['persistence-real-purchases-and-rewards']=(persistent,helpers+r"""
local c=claim(p1,1);economy.EarnGold(p1,50000)
local ok=progression.PurchaseNextHero(p1);assert(ok);advance(.3)
assert(progression.BuyHeroLevels(p1,'Knight','x10'));advance(.3)
assert(progression.BuyUpgrade(p1,'Knight','SharpenedBlade'))
local amount=economy.GetGold(p1);assert(amount<50000 and amount>0)
removePlayer(p1);local fresh=addPlayer(101,'PurchasedRejoin')
assert(economy.GetGold(fresh)==amount and progression.OwnsHero(fresh,'Archer'))
assert(progression.GetHeroLevel(fresh,'Knight')==11 and progression.GetUpgradeState(fresh,'Knight','SharpenedBlade')=='Purchased')
print('PASS: actual reward and authoritative sequential unlock/level/milestone transactions survive leave and rejoin')
""")
scenarios['persistence-two-user-roundtrip']=(persistent,helpers+r"""
local p2=addPlayer(102,'Second');economy.AddGold(p1,100);economy.AddGold(p2,900)
data.SetWave(p1,27);data.SetWave(p2,35);local a=claim(p1,1);local b=claim(p2,4)
assert(a.CurrentWave==27 and b.CurrentWave==35 and b.CurrentEnemy.IsBoss)
removePlayer(p1);assert(b.Active and economy.GetGold(p2)==900)
removePlayer(p2);local newA=addPlayer(101,'A');local newB=addPlayer(102,'B')
assert(economy.GetGold(newA)==100 and economy.GetGold(newB)==900)
assert(claim(newA,2).CurrentWave==27 and claim(newB,5).CurrentWave==35)
print('PASS: independent two-user wave/gold records, cleanup and fresh reclaims')
""")
scenarios['studio-speed-late-humanoid']=('modules.GameConfig.StudioTesting.Enabled=true',r"""
local model=Instance.new('Model');model.Parent=workspace;local root=Instance.new('Part');root.Name='HumanoidRootPart';root.Parent=model;p1.Character=model;p1.CharacterAdded:Fire(model)
local hum=Instance.new('Humanoid');hum.Parent=model;assert(hum.WalkSpeed==32)
print('PASS: character whose Humanoid arrives after CharacterAdded receives configured Studio speed')
""")

scenarios['studio-reset-wave-ui-projectiles']=(allheroes,ui+r"""
local panel=playerGui.IdleHeroSimulatorProgression.CombatDebug
assert(panel.ResetWave.Text=='RESET WAVE' and panel.PlayerSpeed.Text=='PLAYER SPEED: 16')
panel.ResetWave.Activated:Fire();assert(not manager.GetContext(p1),'no active context ignored')
local a=claim(p1,1);advance(.1);local p2=addPlayer(102,'Second');local b=claim(p2,4)
advance(.2);local old=a.CurrentEnemy;local arrowB=active(b,'Archer').Rig.Projectile
assert(active(a,'Archer').Rig.Projectile and arrowB)
local gold=economy.GetGold(p1);local waveConn=a.WaveConnection
panel.ResetWave.Activated:Fire()
assert(a.CurrentEnemy~=old and a.CurrentWave==1 and a.WaveConnection==waveConn)
assert(not active(a,'Archer').Rig.Projectile and not active(a,'Mage').Rig.Projectile)
assert(active(b,'Archer').Rig.Projectile==arrowB and economy.GetGold(p1)==gold)
assert(not originalDamage(active(a,'Archer'),old))
assert(panel.PlayerSpeed.Text=='PLAYER SPEED: 32')
waitForHits(a,'Archer',1);assert(a.CurrentEnemy.Health<a.CurrentEnemy.MaxHealth)
print('PASS: real RESET WAVE button safely gates no-context, cancels only A projectiles, rejects stale damage and resumes attacks; speed display updates')
""")
if __name__=='__main__': run_scenarios(scenarios)
