"""Phase 6C regressions plus every Phase 6B scenario; same Luau/Roblox mock limits."""
from phase6b import scenarios, run_scenarios, ui
scenarios = scenarios.copy()
shop_testing = ('modules.GameConfig.StudioTesting.Enabled=true\n'
                'modules.GameConfig.StudioTesting.StartingGold=2000\n'
                'modules.GameConfig.StudioTesting.StartingOwnedHeroes={Archer=false,Mage=false}\n'
                'modules.EnemyConfig.BaseHealth=1000000000\n')

scenarios['shop-discovery-and-live-ui']=(shop_testing,ui+r'''
local gui=playerGui.IdleHeroSimulatorHeroShop;local panel=gui.Panel
assert(not gui.Enabled and not playerGui.IdleHeroSimulatorProgression.Panel.Visible)
assert(not playerGui.IdleHeroSimulatorProgression.Panel:FindFirstChild('HeroTabs'))
assert(not storage.IdleHeroSimulatorRemotes:FindFirstChild('BuyHero') and progression.BuyHero==nil)
assert(progression.GetNextHero(p1)=='Archer' and p1.HeroShop:GetAttribute('HeroId')=='Archer')
visitShop(p1);assert(gui.Enabled and panel.Hero.Text=='CLAIM AN ISLAND FIRST' and not panel.Buy.Active)
local a=claim(p1,1);visitShop(p1);assert(gui.Enabled and panel.Hero.Text=='ARCHER' and panel.Buy.Text=='BUY ARCHER')
for _,obj in gui:GetDescendants() do
 if obj.ClassName=='TextLabel' or obj.ClassName=='TextButton' then assert(not (obj.Text or ''):find('Mage') and not (obj.Text or ''):find('MAGE')) end
end
assert(panel.Summary.Text:find('Damage: 8',1,true) and panel.Summary.Text:find('1.43 attacks/s',1,true))
economy.SpendGold(p1,2000);assert(panel.Buy.Text=='NOT ENOUGH GOLD' and not panel.Buy.Active)
local old=p1.HeroShop:GetAttribute('OfferToken');panel.Buy.Activated:Fire()
assert(#heroRemote.Requests==0 and not progression.OwnsHero(p1,'Archer'))
economy.AddGold(p1,100);assert(panel.Buy.Active)
panel.Buy.Activated:Fire()
assert(economy.GetGold(p1)==0 and progression.OwnsHero(p1,'Archer') and not progression.OwnsHero(p1,'Mage'))
assert(gui.Enabled and panel.Hero.Text=='MAGE' and panel.Cost.Text=='Cost: 1K Gold')
assert(p1.HeroShop:GetAttribute('OfferToken')~=old and #heroRemote.Requests==1)
-- Replication can deliver descriptive fields after the token; those changes must rerender too.
p1.HeroShop:SetAttribute('HeroName',nil);p1.HeroShop:SetAttribute('HeroName','Mage')
assert(panel.Hero.Text=='MAGE')
p1.HeroShop:SetAttribute('AttackSpeed',0);p1.HeroShop:SetAttribute('AttackSpeed',1/2.4)
assert(panel.Summary.Text:find('0.42 attacks/s',1,true))
assert(#heroRemote.Requests[1]==1 and heroRemote.Requests[1][1]==old,'minimal request is only opaque offer token')
assert(not playerGui.IdleHeroSimulatorProgression.Panel.Visible and not active(a,'Mage'))
assert(manager.GetContext(p1)==a and active(a,'Archer') and #a.Heroes==2)
economy.AddGold(p1,1000);advance(.3);panel.Buy.Activated:Fire()
assert(economy.GetGold(p1)==0 and progression.OwnsHero(p1,'Mage') and not progression.GetNextHero(p1))
assert(panel.Hero.Text=='ALL HEROES UNLOCKED' and not panel.Buy.Visible and panel.Summary.Text=='More heroes coming later.')
panel.Close.Activated:Fire();assert(not gui.Enabled);visitShop(p1)
assert(gui.Enabled and panel.Hero.Text=='ALL HEROES UNLOCKED')
print('PASS: sequential single-offer discovery, no Mage preview, live gold/offer transitions, HUD owned-only, minimal request and usable all-owned merchant')
''')

scenarios['shop-security-replay-and-range']=(shop_testing,ui+r'''
claim(p1,1);visitShop(p1);local token=p1.HeroShop:GetAttribute('OfferToken');local gold=economy.GetGold(p1)
for _,payload in {{},{token,'Mage'},{'Mage'},{'Archer'},{false},{{}},{0/0},{math.huge},{p1},{token,0,p1}} do
 advance(.3);heroRemote.OnServerEvent:Fire(p1,table.unpack(payload))
 assert(economy.GetGold(p1)==gold and not progression.OwnsHero(p1,'Archer') and not progression.OwnsHero(p1,'Mage'))
end
p1.HeroShop:SetAttribute('HeroId','Mage');p1.HeroShop:SetAttribute('Cost',0)
p1.HeroProgression.Mage:SetAttribute('Owned',true);p1:SetAttribute('Gold',1e12)
advance(.3);heroRemote.OnServerEvent:Fire(p1,token)
assert(progression.OwnsHero(p1,'Archer') and not progression.OwnsHero(p1,'Mage') and economy.GetGold(p1)==gold-100)
heroRemote.OnServerEvent:Fire(p1,token);assert(economy.GetGold(p1)==gold-100)
advance(.3);heroRemote.OnServerEvent:Fire(p1,token)
assert(economy.GetGold(p1)==gold-100 and not progression.OwnsHero(p1,'Mage'),'old token after cooldown cannot buy next hero')
local nextToken=p1.HeroShop:GetAttribute('OfferToken')
p1.Character:PivotTo(CFrame.new(0,0,0));advance(.3);heroRemote.OnServerEvent:Fire(p1,nextToken)
assert(economy.GetGold(p1)==gold-100 and not progression.OwnsHero(p1,'Mage'))
visitShop(p1);p1.Character:FindFirstChildOfClass('Humanoid').Health=0;advance(.3);heroRemote.OnServerEvent:Fire(p1,nextToken)
assert(economy.GetGold(p1)==gold-100);p1.Character:FindFirstChildOfClass('Humanoid').Health=100
local p2=addPlayer(102,'Second');visitShop(p2);advance(.3)
heroRemote.OnServerEvent:Fire(p2,nextToken);assert(not progression.OwnsHero(p2,'Archer'))
advance(.3);heroRemote.OnServerEvent:Fire(p1,nextToken)
assert(progression.OwnsHero(p1,'Mage') and economy.GetGold(p1)==gold-1100)
advance(.3);buyNext(p1);assert(economy.GetGold(p1)==gold-1100,'all-owned buy never deducts')
print('PASS: skip/spoof/extra arguments, private costs/gold/ownership, replay/spam, cross-player token, dead/out-of-range and all-owned requests rejected')
''')

scenarios['shop-insufficient-gold-and-config-order']=(shop_testing+r'''
modules.GameConfig.StudioTesting.StartingGold=99
modules.HeroConfig.HeroOrder={'Knight','Mage','Archer'}
''',r'''
claim(p1,1);visitShop(p1);assert(progression.GetNextHero(p1)=='Mage' and p1.HeroShop:GetAttribute('HeroId')=='Mage')
local token=p1.HeroShop:GetAttribute('OfferToken');buyNext(p1)
assert(economy.GetGold(p1)==99 and not progression.OwnsHero(p1,'Mage') and not progression.OwnsHero(p1,'Archer'))
assert(p1.HeroShop:GetAttribute('OfferToken')==token)
economy.AddGold(p1,901);advance(.3);buyNext(p1)
assert(economy.GetGold(p1)==0 and progression.OwnsHero(p1,'Mage') and progression.GetNextHero(p1)=='Archer')
print('PASS: insufficient funds do not change ownership/gold/token; configured HeroOrder determines server discovery without duplicate constants')
''')

scenarios['shop-immediate-active-context']=(shop_testing,ui+r'''
local a=claim(p1,2);local p2=addPlayer(102,'Second');local b=claim(p2,5)
local wave,enemy,knight=a.CurrentWave,a.CurrentEnemy,active(a,'Knight')
local otherEnemy=b.CurrentEnemy;local otherGold=economy.GetGold(p2)
local loops=connected();visitShop(p1);local token=p1.HeroShop:GetAttribute('OfferToken');buyNext(p1)
-- No advance/Heartbeat: a successful shop transaction must add the rig immediately.
assert(active(a,'Archer') and #a.Heroes==2 and not active(b,'Archer'))
assert((active(a,'Archer').Model.PrimaryPart.Position-a.Island.Markers.ArcherSlot.Position).Magnitude<.001)
assert(a.CurrentWave==wave and a.CurrentEnemy==enemy and active(a,'Knight')==knight and connected()==loops)
assert(b.CurrentEnemy==otherEnemy and economy.GetGold(p2)==otherGold)
advance(.3);heroRemote.OnServerEvent:Fire(p1,token)
assert(#a.Heroes==2 and not active(a,'Mage') and economy.GetGold(p1)==1900)
advance(.3);buyNext(p1)
assert(active(a,'Mage') and #a.Heroes==3 and not active(b,'Mage') and connected()==loops)
assert(a.CurrentWave==wave and a.CurrentEnemy==enemy and active(a,'Knight')==knight)
assert((active(a,'Mage').Model.PrimaryPart.Position-a.Island.Markers.MageSlot.Position).Magnitude<.001)
waitForHits(a,'Archer',1);waitForHits(a,'Mage',1)
for _,hit in contextHits(a) do assert(hit.Target.Context==a) end
assert(economy.GetGold(p1)==900 and economy.GetGold(p2)==2000)
removePlayer(p1);assert(not registry.GetStored(p1) and manager.GetContext(p2)==b)
print('PASS: shop adds one rig immediately to own slot/context with no wave/enemy/Knight reset or new loops; correct attacks and owner-only cleanup')
''')

scenarios['shop-before-claim-and-respawn']=(shop_testing,ui+r'''
visitShop(p1);buyNext(p1)
assert(not progression.OwnsHero(p1,'Archer') and not manager.GetContext(p1) and alive('Model','Archer')==0)
assert(economy.GetGold(p1)==2000)
local a=claim(p1,3);visitShop(p1);advance(.3);buyNext(p1)
assert(#a.Heroes==2 and active(a,'Archer') and not active(a,'Mage'))
local enemy=a.CurrentEnemy;local hero=active(a,'Archer')
character(p1)
assert(manager.GetContext(p1)==a and a.CurrentEnemy==enemy and active(a,'Archer')==hero)
assert(not playerGui.IdleHeroSimulatorHeroShop.Enabled)
visitShop(p1);assert(playerGui.IdleHeroSimulatorHeroShop.Panel.Hero.Text=='MAGE')
print('PASS: purchase before island is rejected without Hub combat; claim enables normal crew purchase; avatar reset retains ownership/context and shop reopens current offer')
''')

scenarios['shop-personal-two-client-ui']=(shop_testing,ui+r'''
local a=claim(p1,1);local p2=addPlayer(102,'Second');local b=claim(p2,4)
local gui1=playerGui.IdleHeroSimulatorHeroShop
local gui2parent=Instance.new('PlayerGui');gui2parent.Name='PlayerGui';gui2parent.Parent=p2
local function client(player,fn)
 localPlayer=player;players.LocalPlayer=player;fn()
end
client(p2,function() modules.HeroShopPanel.Start() end)
local gui2=gui2parent.IdleHeroSimulatorHeroShop
assert(not gui1.Enabled and not gui2.Enabled)
visitShop(p1);assert(gui1.Enabled and not gui2.Enabled,'only interacting player opens')
visitShop(p2);client(p2,function() gui2.Panel.Buy.Activated:Fire() end)
assert(gui1.Panel.Hero.Text=='ARCHER' and gui2.Panel.Hero.Text=='MAGE')
assert(not progression.OwnsHero(p1,'Archer') and progression.OwnsHero(p2,'Archer'))
local bGold=economy.GetGold(p2);local bToken=p2.HeroShop:GetAttribute('OfferToken');local bHero=active(b,'Archer')
client(p1,function() gui1.Panel.Buy.Activated:Fire() end)
assert(economy.GetGold(p1)==1900 and economy.GetGold(p2)==bGold and p2.HeroShop:GetAttribute('OfferToken')==bToken)
assert(gui1.Panel.Hero.Text=='MAGE' and gui2.Panel.Hero.Text=='MAGE' and active(b,'Archer')==bHero)
assert(active(a,'Archer') and active(a,'Archer')~=bHero)
client(p2,function() gui2.Panel.Close.Activated:Fire() end);assert(not gui2.Enabled and gui1.Enabled)
visitShop(p2);assert(gui2.Enabled and gui2.Panel.Hero.Text=='MAGE')
print('PASS: shared merchant, two personal client UIs/offers, owner-only open/results/purchases/gold/rigs; B unchanged while A buys')
''')

scenarios['shop-gui-world-lifecycle']=(shop_testing,ui+r'''
local prompt=islandService.GetHeroShopPrompt();local npc=prompt.Parent.Parent
assert(npc.Parent==workspace.IdleHeroSimulatorWorld.Hub and npc.Name=='HeroShop')
assert(prompt.MaxActivationDistance==modules.WorldConfig.HeroShopActivationDistance and prompt.KeyboardKeyCode=='E')
for _,part in npc:GetDescendants() do
 if part:IsA('BasePart') then assert(part.Anchored and part.Transparency==0 and not part.CanCollide) end
end
assert((npc.Head.Position-workspace.IdleHeroSimulatorWorld.Hub.PlayerSpawn.Position).Magnitude>12)
local open=storage.IdleHeroSimulatorRemotes.OpenHeroShop
character(p1);local count=#open.Responses
prompt.Triggered:Fire(p1);assert(#open.Responses==count,'spoofed distant prompt cannot open')
local connections=#open.OnClientEvent.Listeners
for i=1,10 do visitShop(p1);playerGui.IdleHeroSimulatorHeroShop.Panel.Close.Activated:Fire();modules.HeroShopPanel.Start();shop.Start() end
assert(alive('ScreenGui','IdleHeroSimulatorHeroShop')==1 and #open.OnClientEvent.Listeners==connections)
local remoteCount=#storage.IdleHeroSimulatorRemotes:GetChildren()
islandService.Stop();assert(prompt.destroyed and npc.destroyed and not islandService.GetHeroShopPrompt())
assert(not shop.PurchaseNextHero(p1,p1.HeroShop:GetAttribute('OfferToken')))
islandService.Start();assert(islandService.GetHeroShopPrompt()~=prompt and #storage.IdleHeroSimulatorRemotes:GetChildren()==remoteCount)
claim(p1,1);visitShop(p1);advance(.3);buyNext(p1);assert(progression.OwnsHero(p1,'Archer'))
local folder=p1.HeroShop;removePlayer(p1);assert(folder.destroyed)
local replacement=addPlayer(101,'Replacement');assert(replacement.HeroShop:GetAttribute('HeroId')=='Archer')
print('PASS: configurable anchored Hub merchant away from spawn, distance-validated open, GUI/listener/remote uniqueness, world regeneration and player record cleanup')
''')

scenarios['shop-production-and-original-stats']=('isStudio=false\n',ui+r'''
assert(not state.IsAvailable() and not storage:FindFirstChild('IdleHeroSimulatorCombatDebug'))
assert(islandService.GetHeroShopPrompt() and not playerGui.IdleHeroSimulatorHeroShop.Enabled)
assert(modules.HeroConfig.Knight.BaseDamage==20 and modules.HeroConfig.Knight.AttackInterval==1.3)
assert(modules.HeroConfig.Archer.UnlockCost==100 and modules.HeroConfig.Archer.BaseDamage==8 and modules.HeroConfig.Archer.AttackInterval==.7)
assert(modules.HeroConfig.Mage.UnlockCost==1000 and modules.HeroConfig.Mage.BaseDamage==55 and modules.HeroConfig.Mage.AttackInterval==2.4)
visitShop(p1);buyNext(p1);assert(not progression.OwnsHero(p1,'Archer') and economy.GetGold(p1)==0)
assert(not progression.ResetHero(p1,'Knight'))
print('PASS: merchant available in production with actual zero gold, no cheats/debug, unchanged configured hero damage/prices/intervals')
''')

scenarios['shop-deferred-ownership-events']=(shop_testing,r'''
local a=claim(p1,1);visitShop(p1)
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
local oldToken=p1.HeroShop:GetAttribute('OfferToken')
buyNext(p1)
assert(active(a,'Archer') and p1.HeroShop:GetAttribute('HeroId')=='Mage')
local mageToken=p1.HeroShop:GetAttribute('OfferToken');assert(mageToken~=oldToken)
advance(.3);heroRemote.OnServerEvent:Fire(p1,oldToken)
assert(not progression.OwnsHero(p1,'Mage') and economy.GetGold(p1)==1900)
advance(.3);buyNext(p1)
assert(active(a,'Mage') and p1.HeroShop:GetAttribute('AllOwned'))
local finalToken=p1.HeroShop:GetAttribute('OfferToken')
while #queue>0 do table.remove(queue,1)() end
assert(p1.HeroShop:GetAttribute('OfferToken')==finalToken and #a.Heroes==3)
removePlayer(p1)
while #queue>0 do table.remove(queue,1)() end
assert(not registry.GetStored(p1) and alive('Model','Archer')==0)
print('PASS: deferred ownership notifications do not delay personal offer/rig update, invalidate tokens again or leak after player departure')
''')

if __name__ == '__main__':
    run_scenarios(scenarios)
