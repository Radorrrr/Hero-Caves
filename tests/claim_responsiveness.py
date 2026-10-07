"""Actual-module claim detection regressions plus all 53 Phase 6A/B/C/C.1 scenarios.
The deterministic mock does not simulate Roblox physics or real Studio latency.
"""
from phase6c1 import scenarios, run_scenarios
from phase6c import shop_testing, ui

scenarios = scenarios.copy()

scenarios['claim-touch-immediate-and-deduplicated'] = ('', r'''
local island=workspace.IdleHeroSimulatorWorld.Islands.Island1
local model,root=character(p1)
local foot=Instance.new('Part');foot.Name='LeftFoot';foot.Parent=model
model:PivotTo(island.Markers.ClaimZone.CFrame*CFrame.new(0,-1,0))
local claims=0;islandService.Claimed:Connect(function(player,claimed)
 assert(player==p1 and claimed==island);claims+=1
end)
local entry=clock
island.Markers.ClaimZone.Touched:Fire(foot)
local context=manager.GetContext(p1)
assert(context and clock==entry and context.CurrentWave==1)
local avatar=context.Island.OwnerAvatar;local enemy=context.CurrentEnemy
for i=1,5 do island.Markers.ClaimZone.Touched:Fire(root) end
advance(.3)
assert(claims==1 and #thumbnailRequests==1 and connected()==3)
assert(manager.GetContext(p1)==context and context.CurrentEnemy==enemy)
assert(context.Island.OwnerAvatar==avatar and #context.Heroes==1)
assert(alive('Model','CavePlaceholder')==1 and alive('BillboardGui','OwnerAvatar')==1)
assert(p1.RespawnLocation==island.Markers.PlayerSpawn and p1:GetAttribute('IslandId')==1)
print('PASS: any current-character body part can trigger immediate Touched claim; mixed repeated touch/occupancy creates exactly one owner, portrait, cave, Wave 1, Knight and context')
''')

scenarios['claim-premature-touch-recovered-without-reentry'] = ('', r'''
local zone=workspace.IdleHeroSimulatorWorld.Islands.Island2.Markers.ClaimZone
local model,root=character(p1)
model:PivotTo(zone.CFrame*CFrame.new(0,-1,-zone.Size.Z/2-.25))
local foot=Instance.new('Part');foot.Name='LeftFoot';foot.Parent=model
zone.Touched:Fire(foot) -- Foot-first event; root has not yet entered the zone.
assert(not islandService.GetIsland(p1) and not manager.GetContext(p1))
advance(.01) -- Establish the fallback schedule while still outside.
model:PivotTo(zone.CFrame*CFrame.new(0,-1,-zone.Size.Z/2+.25))
local entry=clock
advance(.08);assert(not islandService.GetIsland(p1))
advance(.031)
local context=manager.GetContext(p1)
assert(context and context.Island.Id==2 and clock-entry<=.12)
assert(context.CurrentWave==1 and #context.Heroes==1 and #thumbnailRequests==1)
print('PASS: rejected early foot touch is retried by root occupancy within 0.12s without another touch, jumping or leaving/re-entering')
''')

scenarios['claim-six-rotated-walk-entrances'] = ('', r'''
local owners={p1}
for id=2,6 do owners[id]=addPlayer(100+id,'Walker'..id) end
local count=0;islandService.Claimed:Connect(function() count+=1 end)
for id,player in owners do
 local zone=workspace.IdleHeroSimulatorWorld.Islands['Island'..id].Markers.ClaimZone
 assert(zone.Size.X==20 and zone.Size.Y==8 and zone.Size.Z==12)
 assert(zone.Transparency==1 and not zone.CanCollide and zone.CanTouch and not zone.CanQuery)
 character(player):PivotTo(zone.CFrame*CFrame.new(0,-1,-zone.Size.Z/2-.25))
end
advance(.01);assert(count==0)
for id,player in owners do
 local zone=workspace.IdleHeroSimulatorWorld.Islands['Island'..id].Markers.ClaimZone
 player.Character:PivotTo(zone.CFrame*CFrame.new(0,-1,-zone.Size.Z/2+.25))
end
advance(.12)
assert(count==6 and #thumbnailRequests==6 and connected()==13)
for id,player in owners do
 local context=manager.GetContext(player)
 assert(context and context.Island.Id==id and context.CurrentWave==1)
 assert(context.Island.OwnerAvatar:GetAttribute('OwnerUserId')==player.UserId)
 assert(player.RespawnLocation==context.Island.Markers.PlayerSpawn)
 validateContext(context)
end
print('PASS: all six rotated bridge-side entrances detect normal root height at 3 studs without any Touched event; invisible bounded geometry unchanged')
''')

scenarios['claim-invalid-character-and-zone-bounds'] = ('', r'''
local zone=workspace.IdleHeroSimulatorWorld.Islands.Island3.Markers.ClaimZone
local model,root,hum=character(p1)
for _,offset in {Vector3.new(10.01,0,0),Vector3.new(-10.01,0,0),
 Vector3.new(0,4.01,0),Vector3.new(0,-4.01,0),Vector3.new(0,0,6.01),Vector3.new(0,0,-6.01)} do
 model:PivotTo(zone.CFrame*CFrame.new(offset));advance(.12)
 assert(not islandService.GetIsland(p1))
end
model:PivotTo(zone.CFrame);hum.Health=0;advance(.12)
zone.Touched:Fire(root);assert(not islandService.GetIsland(p1))
hum.Health=100;root.Parent=nil;advance(.12);assert(not islandService.GetIsland(p1))
root.Parent=model;hum.Parent=nil;advance(.12);assert(not islandService.GetIsland(p1))
hum.Parent=model;p1.Character=nil;advance(.12);assert(not islandService.GetIsland(p1))
p1.Character=model;p1.Parent=nil;advance(.12);assert(not islandService.GetIsland(p1))
p1.Parent=players
local oldRoot=root;character(p1) -- New avatar is placed in Hub by CharacterAdded.
zone.Touched:Fire(oldRoot);advance(.12);assert(not islandService.GetIsland(p1))
p1.Character:PivotTo(zone.CFrame);advance(.12)
assert(manager.GetContext(p1) and manager.GetContext(p1).Island.Id==3)
print('PASS: exact oriented volume excludes all six outside faces; dead/missing/late character components, departed player and stale avatar touches cannot claim; valid recovery works')
''')

scenarios['claim-occupancy-race-and-one-island-rule'] = ('', r'''
local p2=addPlayer(102,'Second');local zone=workspace.IdleHeroSimulatorWorld.Islands.Island1.Markers.ClaimZone
character(p1):PivotTo(zone.CFrame);character(p2):PivotTo(zone.CFrame)
local claims=0;islandService.Claimed:Connect(function() claims+=1 end)
advance(.12)
local winner=islandService.GetIslandOwner(1)
local loser=winner==p1 and p2 or p1
assert(winner==p1 or winner==p2)
local context=manager.GetContext(winner)
assert(claims==1 and context and not manager.GetContext(loser) and not islandService.GetIsland(loser))
assert(not loser:GetAttribute('IslandId') and not loser:GetAttribute('HasCombatArea'))
assert(#thumbnailRequests==1 and alive('BillboardGui','OwnerAvatar')==1)
zone.Touched:Fire(loser.Character.HumanoidRootPart)
assert(not manager.GetContext(loser))
local zone2=workspace.IdleHeroSimulatorWorld.Islands.Island2.Markers.ClaimZone
winner.Character:PivotTo(zone2.CFrame);advance(.12)
zone2.Touched:Fire(winner.Character.HumanoidRootPart)
assert(islandService.GetIslandOwner(1)==winner and not islandService.GetIslandOwner(2))
loser.Character:PivotTo(zone2.CFrame);advance(.12)
assert(islandService.GetIslandOwner(2)==loser and claims==2 and #thumbnailRequests==2)
assert(manager.GetContext(winner)==context and connected()==5)
print('PASS: simultaneous fallback occupancy assigns exactly one owner/context/avatar; loser remains eligible for another island despite feedback cooldown; winner cannot own two')
''')

scenarios['claim-mixed-path-race-release-and-reuse'] = ('', r'''
local p2=addPlayer(102,'Second');local zone=workspace.IdleHeroSimulatorWorld.Islands.Island1.Markers.ClaimZone
character(p1):PivotTo(zone.CFrame);character(p2):PivotTo(zone.CFrame)
zone.Touched:Fire(p1.Character.HumanoidRootPart)
local old=manager.GetContext(p1);local avatar=old.Island.OwnerAvatar
advance(.12);assert(not manager.GetContext(p2) and #thumbnailRequests==1)
removePlayer(p1)
assert(avatar.destroyed and not old.Active and not registry.GetStored(p1))
assert(not islandService.GetIslandOwner(1))
advance(.12) -- Waiting player is already inside: no new Touched event.
local fresh=manager.GetContext(p2)
assert(fresh and fresh.Island.Id==1 and fresh.Id~=old.Id and fresh.CurrentWave==1)
assert(fresh.Island.OwnerAvatar~=avatar and fresh.Island.OwnerAvatar:GetAttribute('OwnerUserId')==102)
assert(#thumbnailRequests==2 and alive('BillboardGui','OwnerAvatar')==1 and connected()==3)
local priorAvatar=fresh.Island.OwnerAvatar
islandService.ReleaseIsland(p2)
p2.Character:PivotTo(workspace.IdleHeroSimulatorWorld.Hub.PlayerSpawn.CFrame)
assert(priorAvatar.destroyed and not manager.GetContext(p2))
advance(.12);assert(not islandService.GetIslandOwner(1))
p2.Character:PivotTo(zone.CFrame);advance(.12)
assert(manager.GetContext(p2) and manager.GetContext(p2).Id~=fresh.Id and #thumbnailRequests==3)
print('PASS: Touched winner cannot be double-claimed by fallback; departure releases for stationary waiting player within one poll; explicit release and later reuse clean stale portrait/context')
''')

scenarios['claim-fallback-live-shop-and-respawn'] = (shop_testing, ui+r'''
visitShop(p1);local panel=playerGui.IdleHeroSimulatorHeroShop.Panel
assert(panel.Hero.Text=='CLAIM AN ISLAND FIRST' and not panel.Buy.Active)
buyNext(p1);assert(economy.GetGold(p1)==2000 and not progression.OwnsHero(p1,'Archer'))
local zone=workspace.IdleHeroSimulatorWorld.Islands.Island4.Markers.ClaimZone
p1.Character:PivotTo(zone.CFrame);advance(.12)
local context=manager.GetContext(p1);local avatar=context.Island.OwnerAvatar
assert(panel.Hero.Text=='ARCHER' and panel.Buy.Active and context.CurrentWave==1)
visitShop(p1);advance(.2);panel.Buy.Activated:Fire()
assert(economy.GetGold(p1)==1900 and active(context,'Archer') and #context.Heroes==2)
character(p1)
assert(p1.RespawnLocation==context.Island.Markers.PlayerSpawn)
assert((p1.Character.HumanoidRootPart.Position-(p1.RespawnLocation.Position+Vector3.new(0,3,0))).Magnitude<.001)
p1.Character:PivotTo(CFrame.new(0,-70,0));advance(.22)
assert(p1.Character.HumanoidRootPart.Position.Y>0 and manager.GetContext(p1)==context)
assert(context.Island.OwnerAvatar==avatar and #thumbnailRequests==1)
print('PASS: fallback claim enables already-open shop; authoritative owner purchase adds hero, reset/void preserve exact context/portrait/respawn without duplicate startup')
''')

scenarios['claim-fallback-stop-restart-and-late-player'] = ('', r'''
local late=addPlayer(102,'LateJoin');advance(.12)
assert(not islandService.GetIsland(late))
character(late)
late.Character:PivotTo(workspace.IdleHeroSimulatorWorld.Islands.Island5.Markers.ClaimZone.CFrame)
advance(.12);local first=manager.GetContext(late);assert(first and first.Island.Id==5)
local oldZone=first.Island.Markers.ClaimZone;local portrait=first.Island.OwnerAvatar
islandService.Stop();assert(connected()==0 and portrait.destroyed and not registry.GetStored(late))
oldZone.Touched:Fire(late.Character.HumanoidRootPart);advance(.12)
assert(not islandService.GetIsland(late) and connected()==0)
islandService.Start();assert(connected()==1)
late.Character:PivotTo(workspace.IdleHeroSimulatorWorld.Islands.Island6.Markers.ClaimZone.CFrame)
advance(.12);local second=manager.GetContext(late)
assert(second and second.Island.Id==6 and second.Id~=first.Id and connected()==3)
advance(.3);assert(manager.GetContext(late)==second and #thumbnailRequests==2)
print('PASS: late player/character monitored; Stop removes the sole world heartbeat and old touch listeners; restart uses fresh direct zone references and one detector/context')
''')

if __name__ == '__main__':
    run_scenarios(scenarios)
