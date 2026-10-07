"""Phase 6D actual-module/UI regressions plus every earlier scenario; mock limits apply."""
from claim_responsiveness import scenarios, run_scenarios
from phase6b import ui, allheroes
from phase6c import shop_testing

scenarios = scenarios.copy()
rich = ('modules.GameConfig.StudioTesting.Enabled=true\n'
        'modules.GameConfig.StudioTesting.StartingGold=1000000000000\n'
        'modules.EnemyConfig.BaseHealth=1000000000\n')

scenarios['hero-upgrade-own-menu-compact-hud'] = ('', ui+r'''
local gui=playerGui.IdleHeroSimulatorProgression;local panel=gui.Panel
assert(not panel.Visible and not panel:FindFirstChild('HeroTabs') and not panel:FindFirstChild('CombatOwner'))
assert(gui.Gold.Parent==gui and gui.TotalDPS.Parent==gui and not gui:FindFirstChild('CombatDebug'))
assert(gui.Gold.Text=='GOLD: 0' and gui.TotalDPS.Text=='Total DPS\n0')
local c=claim(p1,1);local h=active(c,'Knight')
assert(h.UpgradePrompt.Parent==h.Model.PrimaryPart and h.UpgradePrompt.ActionText=='Upgrade')
assert(h.UpgradePrompt.ObjectText=='Knight' and h.UpgradePrompt.KeyboardKeyCode=='E')
assert(not h.UpgradePrompt.RequiresLineOfSight and h.UpgradePrompt.MaxActivationDistance==10)
local token=interact(p1,'Knight')
assert(panel.Visible and panel.Hero.Text=='KNIGHT · OWNED' and panel.Level.Text=='Level 1')
assert(panel.Damage.Text=='Damage: 20' and panel.AttackSpeed.Text=='Attack Speed: 0.77 attacks/s')
assert(panel.DPS.Text=='DPS: 15' and panel.GoldMultiplier.Text=='Gold Multiplier: x1')
assert(panel.NextLevelCost.Text:find('10 Gold',1,true) and panel.BuyMode.Text=='BUY MODE: x1')
for _,upgrade in modules.HeroConfig.Knight.Milestones do assert(panel.Milestones:FindFirstChild(upgrade.Id)) end
assert(not panel.Milestones:FindFirstChild('QuickDraw') and not panel.Milestones:FindFirstChild('EnchantedBlade'))
assert(upgrades.IsSelectionValid(p1,'Knight',token))
economy.AddGold(p1,100);assert(gui.Gold.Text=='GOLD: 100' and panel.LevelUp.Active)
panel.Close.Activated:Fire();assert(not panel.Visible and not p1.HeroUpgradeSelection:GetAttribute('Token'))
assert(manager.GetContext(p1)==c and active(c,'Knight')==h)
local fresh=interact(p1,'Knight');assert(fresh~=token and panel.Visible)
print('PASS: hidden contextual panel/no hero tabs; compact live Gold/Total DPS; correct physical prompt/own authoritative stats/milestones; close/reopen keeps combat')
''')

scenarios['hero-upgrade-other-owner-and-unowned-rejected'] = (rich, ui+r'''
local p2=addPlayer(102,'Second');local a=claim(p1,1);local b=claim(p2,4)
local open=storage.IdleHeroSimulatorRemotes.OpenHeroUpgrade;local panel=playerGui.IdleHeroSimulatorProgression.Panel
p1.Character:PivotTo(active(b,'Knight').Model.PrimaryPart.CFrame)
local count=#open.Responses
active(b,'Knight').UpgradePrompt.Triggered:Fire(p1)
assert(#open.Responses==count and not panel.Visible and not p1.HeroUpgradeSelection:GetAttribute('Token'))
assert(not upgrades.Open(p1,active(b,'Knight')))
assert(not active(a,'Archer') and not upgrades.Open(p1,nil))
local owned=active(a,'Knight')
local fake={Id='Archer',Owner=p1,Context=a,Model=owned.Model,UpgradePrompt=owned.UpgradePrompt}
assert(not upgrades.Open(p1,fake),'private HeroesById and ownership must match')
p1.HeroProgression.Archer:SetAttribute('Owned',true)
assert(not upgrades.Open(p1,fake) and not progression.OwnsHero(p1,'Archer'))
local token=interact(p1,'Knight');local levelB=progression.GetHeroLevel(p2,'Knight');local goldB=economy.GetGold(p2)
contextualRequest(storage.IdleHeroSimulatorRemotes.BuyHeroLevels,p1,'Knight','x1')
assert(progression.GetHeroLevel(p1,'Knight')==2 and progression.GetHeroLevel(p2,'Knight')==levelB and economy.GetGold(p2)==goldB)
assert(upgrades.IsSelectionValid(p1,'Knight',token))
print('PASS: another owner and unowned/spoofed hero cannot open; own purchases change only invoking player, never another Knight')
''')

scenarios['hero-upgrade-distance-payload-and-token-security'] = (rich, ui+r'''
local a=claim(p1,1);local p2=addPlayer(102,'Second');local b=claim(p2,4)
local h=active(a,'Knight');local open=storage.IdleHeroSimulatorRemotes.OpenHeroUpgrade
local event=storage.IdleHeroSimulatorRemotes.BuyHeroLevels;local milestone=storage.IdleHeroSimulatorRemotes.BuyUpgrade
character(p1);p1.Character:PivotTo(workspace.IdleHeroSimulatorWorld.Hub.PlayerSpawn.CFrame)
local count=#open.Responses;h.UpgradePrompt.Triggered:Fire(p1)
assert(#open.Responses==count,'distant spoofed prompt must fail')
p1.Character:PivotTo(h.Model.PrimaryPart.CFrame);local hum=p1.Character:FindFirstChildOfClass('Humanoid')
hum.Health=0;h.UpgradePrompt.Triggered:Fire(p1);assert(#open.Responses==count)
hum.Health=100;h.UpgradePrompt.Enabled=false;h.UpgradePrompt.Triggered:Fire(p1);assert(#open.Responses==count)
h.UpgradePrompt.Enabled=true
local token=interact(p1,'Knight');local other=interact(p2,'Knight');local gold=economy.GetGold(p1)
for _,args in {{'Knight','x1'},{'Knight','x1',other},{'Knight','x1',{}},{'Archer','x1',token},
 {'Knight','x1',token,0},{'Knight',10,token},{'Knight','x999',token},{'Knight','x1','forged'}} do
 advance(.3);event.OnServerEvent:Fire(p1,table.unpack(args))
 assert(progression.GetHeroLevel(p1,'Knight')==1 and economy.GetGold(p1)==gold)
end
milestone.OnServerEvent:Fire(p1,'Knight','SharpenedBlade',token,0)
assert(economy.GetGold(p1)==gold)
p1.HeroProgression.Knight.PurchaseModes.x10:SetAttribute('Cost',0)
p1.HeroProgression.Knight.PurchaseModes.x10:SetAttribute('Count',199)
p1.HeroProgression.Knight:SetAttribute('Level',200);p1.HeroUpgradeSelection:SetAttribute('Token','forged')
advance(.3);event.OnServerEvent:Fire(p1,'Knight','x10',token)
assert(progression.GetHeroLevel(p1,'Knight')==11 and economy.GetGold(p1)==gold-mathService.GetBulkLevelCost('Knight',1,10))
assert(progression.GetHeroLevel(p2,'Knight')==1)
hum.Health=0;advance(.3);event.OnServerEvent:Fire(p1,'Knight','x1',token)
assert(progression.GetHeroLevel(p1,'Knight')==11)
print('PASS: range/living character/enabled prompt, exact payload, private owner/hero/token, wrong player/replay/types/price spoof; formulas/gold remain authoritative')
''')

scenarios['hero-upgrade-all-bulk-modes'] = (rich, ui+r'''
local c=claim(p1,1);interact(p1,'Knight');local panel=playerGui.IdleHeroSimulatorProgression.Panel
local event=storage.IdleHeroSimulatorRemotes.BuyHeroLevels
for _,mode in {'x1','x10','x25','x100','MAX','NEXT'} do
 if mode=='MAX' or mode=='NEXT' then assert(progression.ResetHero(p1,'Knight')) end
 local level=progression.GetHeroLevel(p1,'Knight');local gold=economy.GetGold(p1)
 local quote=mathService.GetLevelPurchaseQuote('Knight',level,gold,mode)
 assert(panel.BuyMode.Text=='BUY MODE: '..mode)
 advance(.3);panel.LevelUp.Activated:Fire()
 assert(progression.GetHeroLevel(p1,'Knight')==level+quote.Count)
 assert(economy.GetGold(p1)==gold-quote.Cost)
 assert(panel.Level.Text=='Level '..modules.NumberFormatter.Format(level+quote.Count))
 local response=event.Responses[#event.Responses]
 assert(response[2] and response[4]==quote.Count and response[5]==quote.Cost)
 for _,upgrade in modules.HeroConfig.Knight.Milestones do assert(progression.GetUpgradeState(p1,'Knight',upgrade.Id)~='Purchased') end
 assert(panel.Visible)
 panel.BuyMode.Activated:Fire()
end
assert(panel.BuyMode.Text=='BUY MODE: x1')
print('PASS: x1/x10/x25/x100/MAX/NEXT use unchanged server quote/count/cost/cooldown and never auto-buy milestones')
''')

scenarios['hero-upgrade-milestones-live-effects-and-reset'] = (allheroes+'modules.GameConfig.StudioTesting.StartingHeroLevels={Knight=50,Archer=150,Mage=150}\n', ui+r'''
local p2=addPlayer(102,'Second');local a=claim(p1,1);local b=claim(p2,4)
interact(p1,'Knight');local panel=playerGui.IdleHeroSimulatorProgression.Panel
assert(panel.Milestones.SharpenedBlade.Buy.Text:find('BUY',1,true))
assert(panel.Milestones.SwordMastery.Buy.Text=='LOCKED')
local before=progression.GetHeroDamage(p1,'Knight',false);local gold=economy.GetGold(p1)
local bDamage=progression.GetHeroDamage(p2,'Knight',false)
panel.Milestones.SharpenedBlade.Buy.Activated:Fire()
assert(progression.GetHeroDamage(p1,'Knight',false)>before and economy.GetGold(p1)==gold-100)
assert(panel.Milestones.SharpenedBlade.Buy.Text=='PURCHASED')
assert(progression.GetHeroDamage(p2,'Knight',false)==bDamage)
local rawDamage=panel.Damage.Text
advance(.3);assert(progression.BuyUpgrade(p1,'Mage','EnchantedBlade'))
assert(panel.Damage.Text~=rawDamage,'Mage cross-hero effect must refresh open Knight')
advance(.3);assert(progression.BuyUpgrade(p1,'Mage','AlchemicalFortune'))
assert(panel.GoldMultiplier.Text=='Gold Multiplier: x1.25')
local token=p1.HeroUpgradeSelection:GetAttribute('Token');local h=active(a,'Knight')
advance(.3);storage.IdleHeroSimulatorCombatDebug.Control.OnServerEvent:Fire(p1,'ResetHero','Knight')
assert(panel.Visible and panel.Level.Text=='Level 1' and active(a,'Knight')==h)
assert(panel.Milestones.SharpenedBlade.Buy.Text=='LOCKED' and progression.GetUpgradeState(p1,'Knight','SharpenedBlade')=='Locked')
assert(p1.HeroUpgradeSelection:GetAttribute('Token')==token and progression.GetHeroLevel(p2,'Knight')==50)
assert(panel.Damage.Text=='Damage: '..modules.NumberFormatter.Format(progression.GetHeroDamage(p1,'Knight',false)))
assert(panel.DPS.Text=='DPS: '..modules.NumberFormatter.Format(p1.HeroProgression.Knight:GetAttribute('DPS')))
print('PASS: correct own milestone purchase/states/gold, cross/global effects live refresh, Studio RESET HERO keeps selected physical instance/menu and updates level/stats/costs/milestones without changing B')
''')

scenarios['hero-upgrade-switch-close-stale-results'] = (allheroes, ui+r'''
local a=claim(p1,1);local gui=playerGui.IdleHeroSimulatorProgression;local panel=gui.Panel
local knightToken=interact(p1,'Knight');local mageToken=interact(p1,'Mage')
assert(knightToken~=mageToken and panel.Hero.Text=='MAGE · OWNED')
assert(panel.Milestones.EnchantedBlade and not panel.Milestones:FindFirstChild('SharpenedBlade'))
assert(alive('ScreenGui','IdleHeroSimulatorProgression')==1)
local event=storage.IdleHeroSimulatorRemotes.BuyHeroLevels
local gold=economy.GetGold(p1);event.OnServerEvent:Fire(p1,'Knight','x100',knightToken)
assert(economy.GetGold(p1)==gold and progression.GetHeroLevel(p1,'Knight')==1)
assert(panel.PurchaseResult.Text=='','response for old selection must be ignored')
storage.IdleHeroSimulatorRemotes.HeroUpgradeClosed:FireClient(p1,knightToken)
assert(panel.Visible,'late close of old selection cannot close Mage')
storage.IdleHeroSimulatorRemotes.CloseHeroUpgrade.OnServerEvent:Fire(p1,knightToken)
assert(upgrades.IsSelectionValid(p1,'Mage',mageToken))
panel.Close.Activated:Fire();assert(not panel.Visible)
event.OnServerEvent:Fire(p1,'Mage','x1',mageToken)
assert(progression.GetHeroLevel(p1,'Mage')==1 and economy.GetGold(p1)==gold)
for i=1,8 do interact(p1,'Archer');panel.Close.Activated:Fire() end
assert(alive('ScreenGui','IdleHeroSimulatorProgression')==1 and manager.GetContext(p1)==a)
print('PASS: one menu switches only physical selection/milestones; old tokens/results/close messages cannot affect new hero; CLOSE revokes selection; repeated reopen creates no GUI stack')
''')

scenarios['hero-upgrade-despawn-context-recreation'] = (rich, ui+r'''
local c=claim(p1,1);local h=active(c,'Knight');local token=interact(p1,'Knight')
local panel=playerGui.IdleHeroSimulatorProgression.Panel;local event=storage.IdleHeroSimulatorRemotes.BuyHeroLevels
local gold=economy.GetGold(p1)
h.Model:Destroy();assert(not panel.Visible and not p1.HeroUpgradeSelection:GetAttribute('Token'))
event.OnServerEvent:Fire(p1,'Knight','x1',token);assert(economy.GetGold(p1)==gold)
advance(.01);local replacement=active(c,'Knight');assert(replacement and replacement~=h and replacement.UpgradePrompt)
assert(alive('ProximityPrompt','UpgradeHero')==1)
local island=c.Island;local nextToken=interact(p1,'Knight');manager.StopCombat(p1)
assert(not panel.Visible and not p1.HeroUpgradeSelection:GetAttribute('Token'))
event.OnServerEvent:Fire(p1,'Knight','x1',nextToken);assert(economy.GetGold(p1)==gold)
manager.StartCombat(p1,island);local recreated=manager.GetContext(p1)
assert(recreated and recreated.Id~=c.Id and alive('ProximityPrompt','UpgradeHero')==1)
local token3=interact(p1,'Knight');islandService.ReleaseIsland(p1)
assert(not panel.Visible and alive('ProximityPrompt','UpgradeHero')==0)
p1.Character:PivotTo(workspace.IdleHeroSimulatorWorld.Hub.PlayerSpawn.CFrame)
event.OnServerEvent:Fire(p1,'Knight','x1',token3);assert(economy.GetGold(p1)==gold)
local new=claim(p1,1);assert(new and alive('ProximityPrompt','UpgradeHero')==1)
print('PASS: physical destruction, context cleanup, release and recreation immediately close/revoke stale selection, regenerate exactly one prompt and preserve private progress')
''')

scenarios['hero-upgrade-avatar-reset-and-void'] = (rich, ui+r'''
local c=claim(p1,1);local token=interact(p1,'Knight');local panel=playerGui.IdleHeroSimulatorProgression.Panel
local h=active(c,'Knight');character(p1)
assert(not panel.Visible and not upgrades.IsSelectionValid(p1,'Knight',token))
assert(manager.GetContext(p1)==c and active(c,'Knight')==h and alive('ProximityPrompt','UpgradeHero')==1)
local token2=interact(p1,'Knight');p1.Character:PivotTo(CFrame.new(0,-70,0));advance(.22)
assert(manager.GetContext(p1)==c and p1.Character.HumanoidRootPart.Position.Y>0)
assert(panel.Visible and upgrades.IsSelectionValid(p1,'Knight',token2))
print('PASS: avatar respawn closes/revokes old menu without rebuilding heroes; void return preserves the valid context/hero/menu and movement is free')
''')

scenarios['hero-upgrade-purchased-and-preowned-heroes'] = (shop_testing, ui+r'''
local c=claim(p1,1);assert(active(c,'Knight').UpgradePrompt and not active(c,'Archer'))
visitShop(p1);buyNext(p1);local archer=active(c,'Archer');assert(archer and archer.UpgradePrompt)
local token=interact(p1,'Archer');local panel=playerGui.IdleHeroSimulatorProgression.Panel
assert(panel.Visible and panel.Hero.Text=='ARCHER · OWNED' and panel.Milestones.QuickDraw)
visitShop(p1);advance(.3);buyNext(p1);local mage=active(c,'Mage');assert(mage and mage.UpgradePrompt)
interact(p1,'Mage');assert(panel.Hero.Text=='MAGE · OWNED' and not panel.Milestones:FindFirstChild('QuickDraw'))
local h=active(c,'Knight');heroes.RefreshOwnedHeroes(c);heroes.Start(c)
assert(alive('ProximityPrompt','UpgradeHero')==3)
islandService.ReleaseIsland(p1);local fresh=claim(p1,2)
assert(#fresh.Heroes==3 and alive('ProximityPrompt','UpgradeHero')==3)
for _,hero in fresh.Heroes do assert(hero.UpgradePrompt.Parent==hero.Model.PrimaryPart) end
assert(not upgrades.IsSelectionValid(p1,'Archer',token))
print('PASS: Knight startup, newly purchased Archer/Mage and pre-owned crew at reclaim each get exactly one instance-bound interaction; Hero Shop remains separate')
''')

scenarios['hero-upgrade-combat-waves-popups-while-open'] = ('', ui+r'''
local c=claim(p1,1);local token=interact(p1,'Knight');local gui=playerGui.IdleHeroSimulatorProgression
local connections=connected();local startPosition=p1.Character.HumanoidRootPart.Position
advance(.6)
assert(gui.Panel.Visible and gui.GoldGain.Text=='+5 Gold' and gui.Gold.Text=='GOLD: 5')
assert(connected()==connections and #contextHits(c,'Knight')>0)
advance(1.2);assert(c.CurrentWave==2 and gui.Panel.Visible)
assert((p1.Character.HumanoidRootPart.Position-startPosition).Magnitude<.001)
local characterHum=p1.Character:FindFirstChildOfClass('Humanoid');assert(not characterHum.PlatformStand)
p1.Character:PivotTo(workspace.IdleHeroSimulatorWorld.Hub.PlayerSpawn.CFrame)
assert(gui.Panel.Visible and upgrades.IsSelectionValid(p1,'Knight',token),'movement/range exit does not freeze or close a valid selection')
local enemy=enemies.Spawn(c,5,true);local deadline=enemy.Deadline
advance(1.1);assert(enemy.Deadline==deadline and enemy.Model:GetAttribute('TimeRemaining')<30 and gui.Panel.Visible)
gui.Panel.Close.Activated:Fire();assert(connected()==connections and manager.GetContext(p1)==c)
print('PASS: menu/close never pause or restart attack loops/waves/boss deadline; reward popup and compact gold work independently; no movement lock')
''')

scenarios['hero-upgrade-six-owners-identical-heroids'] = (allheroes, r'''
local owners={p1};local contexts={};local tokens={}
for i=2,6 do owners[i]=addPlayer(100+i,'Owner'..i) end
for i,player in owners do
 contexts[i]=claim(player,i);tokens[i]=interact(player,'Knight')
 assert(upgrades.IsSelectionValid(player,'Knight',tokens[i]))
 for j=1,6 do if j~=i and contexts[j] then assert(not upgrades.Open(player,active(contexts[j],'Knight'))) end end
end
assert(alive('ProximityPrompt','UpgradeHero')==18 and connected()==13)
for i,player in owners do
 local beforeGold=economy.GetGold(player)
 contextualRequest(storage.IdleHeroSimulatorRemotes.BuyHeroLevels,player,'Knight','x10')
 assert(progression.GetHeroLevel(player,'Knight')==11 and economy.GetGold(player)==beforeGold-mathService.GetBulkLevelCost('Knight',1,10))
 assert(progression.GetHeroLevel(player,'Archer')==1)
end
local one=active(contexts[1],'Knight');local p2=owners[2]
p2.Character:PivotTo(one.Model.PrimaryPart.CFrame);assert(not upgrades.Open(p2,one))
removePlayer(owners[3]);assert(alive('ProximityPrompt','UpgradeHero')==15)
for i,player in owners do if i~=3 then assert(upgrades.IsSelectionValid(player,'Knight',tokens[i])) end end
print('PASS: six active owner contexts/18 unique physical prompts; same HeroId actions remain private; one owner departure removes only its selections/three prompts')
''')

scenarios['hero-upgrade-two-client-ui-isolation'] = (rich, ui+r'''
local a=claim(p1,1);local p2=addPlayer(102,'Second');local b=claim(p2,4)
local gui2parent=Instance.new('PlayerGui');gui2parent.Name='PlayerGui';gui2parent.Parent=p2
local function client(player,fn) localPlayer=player;players.LocalPlayer=player;fn() end
client(p2,function()
''' + ui + r'''
end)
local gui1=playerGui.IdleHeroSimulatorProgression;local gui2=gui2parent.IdleHeroSimulatorProgression
interact(p1,'Knight');assert(gui1.Panel.Visible and not gui2.Panel.Visible)
interact(p2,'Knight');assert(gui2.Panel.Visible and gui2.Panel.Level.Text=='Level 1')
local bGold=economy.GetGold(p2)
client(p1,function() gui1.Panel.LevelUp.Activated:Fire() end)
assert(gui1.Panel.Level.Text=='Level 2' and gui2.Panel.Level.Text=='Level 1' and economy.GetGold(p2)==bGold)
client(p2,function() gui2.Panel.BuyMode.Activated:Fire();gui2.Panel.LevelUp.Activated:Fire() end)
assert(gui2.Panel.Level.Text=='Level 11' and gui1.Panel.Level.Text=='Level 2')
client(p1,function() gui1.Panel.Close.Activated:Fire() end)
p1.Character:PivotTo(active(b,'Knight').Model.PrimaryPart.CFrame)
active(b,'Knight').UpgradePrompt.Triggered:Fire(p1)
assert(not gui1.Panel.Visible and gui2.Panel.Visible)
client(p2,function() gui2.Panel.Close.Activated:Fire() end)
assert(not gui2.Panel.Visible and not gui1.Panel.Visible)
assert(alive('ScreenGui','IdleHeroSimulatorProgression')==2)
print('PASS: two real client-script instances get only own prompt events/stats/level results and closes; identical Knights remain isolated and foreign prompt does not open')
''')

scenarios['hero-upgrade-deferred-selection-and-release-safety'] = (allheroes, ui+r'''
local c=claim(p1,1);local h=active(c,'Knight')
local old=interact(p1,'Knight')
local queuedAncestry=h.Model.AncestryChanged.Listeners[#h.Model.AncestryChanged.Listeners].fn
local current=interact(p1,'Archer');local panel=playerGui.IdleHeroSimulatorProgression.Panel
queuedAncestry() -- Simulate a late callback captured before disconnection/switch.
assert(panel.Visible and panel.Hero.Text=='ARCHER · OWNED')
assert(upgrades.IsSelectionValid(p1,'Archer',current))
local queue={}
islandService.Releasing.Fire=function(self,...)
 local args=table.pack(...)
 for _,connection in self.Listeners do
  if connection.connected then table.insert(queue,function() connection.fn(table.unpack(args,1,args.n)) end) end
 end
end
local gold=economy.GetGold(p1)
islandService.ReleaseIsland(p1)
p1.Character:PivotTo(workspace.IdleHeroSimulatorWorld.Hub.PlayerSpawn.CFrame)
assert(not registry.IsActive(c))
storage.IdleHeroSimulatorRemotes.BuyHeroLevels.OnServerEvent:Fire(p1,'Archer','x100',current)
assert(economy.GetGold(p1)==gold and progression.GetHeroLevel(p1,'Archer')==1 and not panel.Visible)
for _,fn in queue do fn() end
assert(not registry.GetStored(p1) and alive('ProximityPrompt','UpgradeHero')==0)
assert(not upgrades.IsSelectionValid(p1,'Knight',old))
print('PASS: delayed old ancestry callback cannot close new selection; private ownership rejects stale purchases before deferred release cleanup, then closes menu and removes prompts')
''')

if __name__ == '__main__':
    run_scenarios(scenarios)
