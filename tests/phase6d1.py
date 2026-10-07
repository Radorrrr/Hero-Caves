"""Two UX changes plus all Phase 6D regressions; per-client Enabled is mocked separately."""
from phase6d import scenarios, run_scenarios, rich
from phase6b import ui, allheroes
from phase6c import shop_testing
scenarios=scenarios.copy()
views=r'''
local function view(player,fn)
 local oldRuntime,oldPlayer,oldLocal=clientRuntime,localPlayer,players.LocalPlayer
 clientRuntime=true;localPlayer=player;players.LocalPlayer=player
 local result=fn()
 clientRuntime,localPlayer,players.LocalPlayer=oldRuntime,oldPlayer,oldLocal
 return result
end
local function visible(player,prompt) return view(player,function() return prompt.Enabled end) end
local visibility=modules.HeroPromptVisibility
'''
scenarios['polish-left-layout-and-switch']=(allheroes,ui+r'''
local c=claim(p1,1);local gui=playerGui.IdleHeroSimulatorProgression;local panel=gui.Panel
assert(panel.AnchorPoint[1]==0 and panel.AnchorPoint[2]==0)
assert(panel.Position[1]==16 and panel.Position[2]==72 and panel.Size[4]==-72)
assert(gui.Gold.Position[2]==12 and gui.Gold.Size[2]==36,'Gold ends at y48; panel starts y72')
assert(gui.TotalDPS.Position[1]==1 and gui.TotalDPS.Position[2]==-16)
for _,id in {'Knight','Archer','Mage','Knight'} do
 interact(p1,id);assert(panel.Visible and panel.Hero.Text==string.upper(id)..' · OWNED')
 assert(panel.Position[1]==16 and panel.Position[2]==72 and panel.AnchorPoint[1]==0)
 assert(panel.Level and panel.Damage and panel.AttackSpeed and panel.DPS and panel.GoldMultiplier)
 assert(panel.BuyMode and panel.LevelUp and panel.Milestones and panel.Close)
end
panel.Close.Activated:Fire();assert(not panel.Visible and manager.GetContext(p1)==c)
print('PASS: left 16px/72px menu below unchanged Gold HUD, Total DPS visible; same position/contents for Knight/Archer/Mage and close/switch')
''')
scenarios['polish-local-owner-foreign-and-shop']=(allheroes,ui+views+r'''
local a=claim(p1,1);local p2=addPlayer(102,'Second');local b=claim(p2,4)
view(p2,function() visibility.Start() end)
for _,id in {'Knight','Archer','Mage'} do
 local own=active(a,id);local foreign=active(b,id)
 assert(own.Model:GetAttribute('OwnerUserId')==101 and own.Model:GetAttribute('HeroId')==id and own.Model:GetAttribute('ContextId')==a.Id)
 assert(visible(p1,own.UpgradePrompt) and not visible(p2,own.UpgradePrompt))
 assert(visible(p2,foreign.UpgradePrompt) and not visible(p1,foreign.UpgradePrompt))
 assert(own.UpgradePrompt.Enabled and foreign.UpgradePrompt.Enabled,'local changes must not change server Enabled')
 p2.Character:PivotTo(own.Model.PrimaryPart.CFrame)
 assert(not upgrades.Open(p2,own),'foreign interaction remains rejected by private server records')
end
local shopPrompt=islandService.GetHeroShopPrompt()
assert(visible(p1,shopPrompt) and visible(p2,shopPrompt) and shopPrompt.Enabled)
local connections=#workspace.DescendantAdded.Listeners
view(p1,function() visibility.Start() end);view(p2,function() visibility.Start() end)
assert(#workspace.DescendantAdded.Listeners==connections,'filter initialization idempotent')
interact(p1,'Knight');assert(playerGui.IdleHeroSimulatorProgression.Panel.Visible)
print('PASS: all three heroes owner-only on each client, private server security remains, shared merchant unaffected and one event-driven filter per client')
''')
scenarios['polish-dynamic-purchases-recreation-reuse']=(shop_testing,ui+views+r'''
local a=claim(p1,1);local p2=addPlayer(102,'Second');local b=claim(p2,4)
view(p2,function() visibility.Start() end)
for _,id in {'Archer','Mage'} do
 visitShop(p1);advance(.3);buyNext(p1)
 local h=active(a,id)
 assert(h and h.Model:GetAttribute('OwnerUserId')==101 and h.Model:GetAttribute('ContextId')==a.Id)
 assert(visible(p1,h.UpgradePrompt) and not visible(p2,h.UpgradePrompt))
 assert(not active(b,id))
end
local island=a.Island;local old=active(a,'Knight').UpgradePrompt
manager.StopCombat(p1);manager.StartCombat(p1,island);local fresh=manager.GetContext(p1)
assert(fresh.Id~=a.Id and old.destroyed)
for _,h in fresh.Heroes do
 assert(h.Model:GetAttribute('OwnerUserId')==101 and h.Model:GetAttribute('ContextId')==fresh.Id)
 assert(visible(p1,h.UpgradePrompt) and not visible(p2,h.UpgradePrompt))
end
removePlayer(p1);islandService.ReleaseIsland(p2);local reused=claim(p2,1)
local h=active(reused,'Knight')
assert(h.Model:GetAttribute('OwnerUserId')==102 and h.Model:GetAttribute('ContextId')==reused.Id)
assert(visible(p2,h.UpgradePrompt) and not visible(p1,h.UpgradePrompt))
assert(h.UpgradePrompt.Enabled and alive('ProximityPrompt','UpgradeHero')==1)
print('PASS: post-start claims/shop Archer/Mage/context recreation/owner leave/island reuse get correct current metadata and owner-only visibility without rejoin')
''')
scenarios['polish-delayed-metadata-and-listener-cleanup']=('',ui+views+r'''
local p2=addPlayer(102,'Second');view(p2,function() visibility.Start() end)
local model=Instance.new('Model');model.Name='ArbitraryModelName';model.Parent=workspace
local root=Instance.new('Part');root.Parent=model
local prompt=Instance.new('ProximityPrompt');prompt.Name='UpgradeHero';prompt.Enabled=true;prompt.Parent=root
assert(not visible(p1,prompt) and not visible(p2,prompt))
model:SetAttribute('OwnerUserId',101);model:SetAttribute('HeroId','Knight')
assert(not visible(p1,prompt),'missing context metadata fails closed')
model:SetAttribute('ContextId','101:late')
assert(visible(p1,prompt) and not visible(p2,prompt))
model:SetAttribute('OwnerUserId',102)
assert(visible(p2,prompt) and not visible(p1,prompt),'metadata changes must re-filter both clients')
model:SetAttribute('ContextId',nil);assert(not visible(p1,prompt) and not visible(p2,prompt))
model:SetAttribute('ContextId','102:new')
local function connectedMetadata()
 local n=0;for _,signal in model.AttributeSignals do for _,connection in signal.Listeners do if connection.connected then n+=1 end end end;return n
end
assert(connectedMetadata()==6)
prompt.Parent=nil;assert(connectedMetadata()==0)
prompt.Parent=root;assert(connectedMetadata()==6 and visible(p2,prompt) and not visible(p1,prompt))
model:Destroy();assert(connectedMetadata()==0)
assert(islandService.GetHeroShopPrompt().Enabled)
print('PASS: delayed/reordered or changing metadata fails closed then updates locally; arbitrary model name, reparent and destruction disconnect/rebind listeners; shop unchanged')
''')
if __name__=='__main__':
 run_scenarios(scenarios)
