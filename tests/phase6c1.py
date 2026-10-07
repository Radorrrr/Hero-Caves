"""Phase 6C.1 plus all migrated Phase 6A/B/C regressions (source-level simulations)."""
from phase6c import scenarios, run_scenarios, ui, shop_testing
scenarios = scenarios.copy()

scenarios['island-gated-shop-live-state']=(shop_testing,ui+r'''
visitShop(p1);local panel=playerGui.IdleHeroSimulatorHeroShop.Panel
assert(panel.Hero.Text=='CLAIM AN ISLAND FIRST' and not panel.Buy.Active)
assert(panel.Summary.Text=='Claim an island before purchasing heroes.')
panel.Buy.Activated:Fire();assert(#heroRemote.Requests==0)
local token=p1.HeroShop:GetAttribute('OfferToken');buyNext(p1)
assert(heroRemote.Responses[#heroRemote.Responses][3]=='ClaimIslandFirst')
assert(economy.GetGold(p1)==2000 and not progression.OwnsHero(p1,'Archer') and not manager.GetContext(p1))
p1:SetAttribute('IslandId',1);assert(panel.Buy.Active,'simulate spoofed client display')
advance(.3);heroRemote.OnServerEvent:Fire(p1,token)
assert(heroRemote.Responses[#heroRemote.Responses][3]=='ClaimIslandFirst')
assert(not islandService.GetIsland(p1) and economy.GetGold(p1)==2000 and not progression.OwnsHero(p1,'Archer'))
p1:SetAttribute('IslandId',nil)
local context=claim(p1,1)
assert(panel.Hero.Text=='ARCHER' and panel.Buy.Active,'open shop must update on claim')
visitShop(p1);advance(.3);panel.Buy.Activated:Fire()
assert(active(context,'Archer') and economy.GetGold(p1)==1900 and panel.Hero.Text=='MAGE')
islandService.ReleaseIsland(p1)
assert(panel.Hero.Text=='CLAIM AN ISLAND FIRST' and not panel.Buy.Active)
advance(.3);buyNext(p1)
assert(economy.GetGold(p1)==1900 and not progression.OwnsHero(p1,'Mage') and not manager.GetContext(p1))
print('PASS: no-island UI gate and authoritative rejection despite spoofed IslandId, unchanged money/ownership/no Hub combat; live claim/release state and normal owner purchase')
''')

scenarios['six-owner-headshots-cleanup-reuse']=('',r'''
local contexts={};local owners={p1}
for i=2,6 do owners[i]=addPlayer(100+i,'Owner'..i) end
for i=1,6 do
 local c=claim(owners[i],i);contexts[i]=c
 local avatar=c.Island.OwnerAvatar
 assert(avatar and avatar:GetAttribute('OwnerUserId')==owners[i].UserId)
 assert(avatar.Headshot.Image:find('id='..owners[i].UserId..'&',1,true))
 assert(avatar.OwnerName.Text==owners[i].DisplayName.."'s Cave" and not c.Island.Label.Parent.Enabled)
 assert(not avatar.Headshot.Fallback.Visible and avatar.Adornee==c.Island.Markers.ClaimZone)
 assert(avatar.MaxDistance==modules.WorldConfig.OwnerAvatarMaxDistance and not avatar.AlwaysOnTop)
 assert(avatar.Headshot.Size[1]==88 and avatar.Headshot.Position[1]==.5)
end
assert(#thumbnailRequests==6)
local oldIsland=contexts[3].Island;local old=oldIsland.OwnerAvatar
islandService.ReleaseIsland(owners[3])
assert(old.destroyed and not oldIsland.OwnerAvatar and oldIsland.Label.Parent.Enabled)
assert(oldIsland.Label.Text=='UNCLAIMED' and oldIsland.Model:GetAttribute('OwnerUserId')==0)
local replacement=addPlayer(200,'NewOwner');local fresh=claim(replacement,3)
assert(fresh.Island==oldIsland and oldIsland.OwnerAvatar~=old)
assert(oldIsland.OwnerAvatar:GetAttribute('OwnerUserId')==200 and oldIsland.OwnerAvatar.Headshot.Image:find('id=200&',1,true))
assert(oldIsland.OwnerAvatar.OwnerName.Text=="NewOwner's Cave")
for i=1,6 do if i~=3 then assert(contexts[i].Island.OwnerAvatar:GetAttribute('OwnerUserId')==owners[i].UserId) end end
removePlayer(replacement);assert(not oldIsland.OwnerAvatar and oldIsland.Label.Text=='UNCLAIMED')
print('PASS: supported thumbnail API, six independent correct owner portraits/names, stacked frame, release/leave cleanup and new owner icon on reuse')
''')

scenarios['headshot-delayed-and-failed-loads']=('',r'''
local spawn=task.spawn;local queue={}
local p2=addPlayer(102,'Second') -- Load synchronously; only thumbnail work is deferred below.
task.spawn=function(fn,...) local args=table.pack(...);table.insert(queue,function() fn(table.unpack(args,1,args.n)) end) end
local a=claim(p1,1);local island=a.Island;local old=island.OwnerAvatar;local oldImage=old.Headshot
assert(old.Headshot.Image=='' and old.Headshot.Fallback.Visible and a.CurrentEnemy and active(a,'Knight'))
islandService.ReleaseIsland(p1)
local b=claim(p2,1);local fresh=island.OwnerAvatar
assert(#queue==2 and old.destroyed and fresh:GetAttribute('OwnerUserId')==102)
queue[1]();assert(fresh.Headshot.Image=='' and oldImage.Image=='','stale answer cannot write a reused/removed GUI')
queue[2]();assert(fresh.Headshot.Image:find('id=102&',1,true) and not fresh.Headshot.Fallback.Visible)
task.spawn=spawn
islandService.ReleaseIsland(p2)
local fetch=players.GetUserThumbnailAsync
players.GetUserThumbnailAsync=function() error('thumbnail service unavailable') end
local c=claim(p1,1)
assert(c.CurrentWave==1 and active(c,'Knight') and c.CurrentEnemy)
assert(island.OwnerAvatar.Headshot.Image=='' and island.OwnerAvatar.Headshot.Fallback.Visible)
assert(island.OwnerAvatar.OwnerName.Text==p1.DisplayName.."'s Cave")
islandService.ReleaseIsland(p1)
players.GetUserThumbnailAsync=function() return 'not-ready',false end
local d=claim(p2,1);assert(d and island.OwnerAvatar.Headshot.Fallback.Visible and island.OwnerAvatar.Headshot.Image=='')
players.GetUserThumbnailAsync=fetch
removePlayer(p2);assert(not island.OwnerAvatar)
print('PASS: yielding/delayed headshots cannot block claim/combat or overwrite reused island; failed/not-ready thumbnails retain correct named fallback and cleanup')
''')

legacy_setup=r'''
local function oldSpawn(name,position,parent)
 local spawn=Instance.new('SpawnLocation');spawn.Name=name;spawn.Size=Vector3.new(12,1,12)
 spawn.CFrame=CFrame.new(position);spawn.Anchored=true;spawn.Transparency=0;spawn.CanCollide=true
 spawn.CastShadow=true;spawn.Enabled=true;spawn.Neutral=true;spawn.Parent=parent or workspace
 return spawn
end
local legacy=oldSpawn('SpawnLocation',Vector3.new(0,.5,0))
local folder=Instance.new('Model');folder.Name='LegacyHub';folder.Parent=workspace
local nested=oldSpawn('OldSpawn',Vector3.new(10,1,10),folder)
local distant=oldSpawn('DistantSpawn',Vector3.new(400,1,400))
'''
scenarios['invisible-spawns-centered-title-and-recovery']=(legacy_setup,r'''
local hub=workspace.IdleHeroSimulatorWorld.Hub;local spawn=hub.PlayerSpawn
assert(workspace.IdleHeroSimulatorWorld:GetAttribute('HiddenLegacyHubSpawns')==2)
for _,s in {legacy,nested,spawn} do
 assert(s.Transparency==1 and not s.CanCollide and not s.CastShadow and s.Enabled)
 assert(s.SpawnTexture.Transparency==1)
 local decal=Instance.new('Decal');decal.Transparency=0;decal.Parent=s;assert(decal.Transparency==1)
 local texture=Instance.new('Texture');texture.Transparency=0;texture.Parent=s;assert(texture.Transparency==1)
end
assert(distant.Transparency==0 and distant.SpawnTexture.Transparency==0,'unrelated outside spawn unaffected')
local anchor=hub.Platform.HubTitleAnchor;local title=anchor.HubTitle
local expected=modules.WorldConfig.HubPosition+Vector3.new(0,modules.WorldConfig.HubSize.Y/2+modules.WorldConfig.HubTitleHeight,0)
assert((anchor.WorldPosition-expected).Magnitude<.001 and title.Adornee==anchor)
assert(title.StudsOffset.Magnitude==0 and title.StudsOffsetWorldSpace.Magnitude==0)
assert(title.Owner.Text=='IDLE HERO SIMULATOR · HUB' and title.Owner.TextXAlignment=='Center')
assert(not spawn:FindFirstChild('OwnershipDisplay') and anchor.Parent==hub.Platform and not title.AlwaysOnTop)
local c,root=character(p1)
assert(p1.RespawnLocation==spawn and (root.Position-(spawn.Position+Vector3.new(0,3,0))).Magnitude<.001)
root.CFrame=CFrame.new(0,-100,0);root.AssemblyLinearVelocity=Vector3.new(0,-200,0)
advance(.21);assert((root.Position-(spawn.Position+Vector3.new(0,3,0))).Magnitude<.001)
assert(root.AssemblyLinearVelocity.Magnitude==0)
local context=claim(p1,6);local island=context.Island;local portrait=island.OwnerAvatar;local enemy=context.CurrentEnemy
local reset,resetRoot=character(p1)
assert(p1.RespawnLocation==island.Markers.PlayerSpawn and manager.GetContext(p1)==context and context.CurrentEnemy==enemy)
assert((resetRoot.Position-(island.Markers.PlayerSpawn.Position+Vector3.new(0,3,0))).Magnitude<.001)
assert(island.OwnerAvatar==portrait)
resetRoot.CFrame=CFrame.new(0,-100,0);advance(.21)
assert((resetRoot.Position-(island.Markers.PlayerSpawn.Position+Vector3.new(0,3,0))).Magnitude<.001)
assert(manager.GetContext(p1)==context and island.OwnerAvatar==portrait)
print('PASS: legacy/generated/late spawn decals invisible with spawn functionality preserved; central world-space title independent of offset spawn; Hub/island resets and void return preserve combat/portrait')
''')

scenarios['personal-wave-labels-normal-boss-transitions']=('',r'''
local a=claim(p1,1);local p2=addPlayer(102,'Second');local b=claim(p2,2)
heroes.Stop(a);heroes.Stop(b)
assert(a.CurrentEnemy.WaveLabel.Text=='WAVE 1' and b.CurrentEnemy.WaveLabel.Text=='WAVE 1')
local second=b.CurrentEnemy
enemies.Damage(a,a.CurrentEnemy.Health);advance(1.05)
assert(a.CurrentWave==2 and a.CurrentEnemy.WaveLabel.Text=='WAVE 2')
assert(b.CurrentWave==1 and b.CurrentEnemy==second and second.WaveLabel.Text=='WAVE 1')
for wave=2,4 do enemies.Damage(a,a.CurrentEnemy.Health);advance(1.05) end
local boss=a.CurrentEnemy
assert(a.CurrentWave==5 and boss.WaveLabel.Text=='WAVE 5 · BOSS' and boss.Model:GetAttribute('Wave')==5)
assert(boss.NameLabel.Text:find('Boss Slime',1,true) and boss.NameLabel.Text:find('30s',1,true))
assert(boss.HealthLabel.Text=='330 / 330 HP' and boss.HealthFill.Size[1]==1)
local deadline=boss.Deadline;advance(1.1)
assert(boss.NameLabel.Text:find('29s',1,true) and boss.WaveLabel.Text=='WAVE 5 · BOSS')
assert(enemies.ResetHealth(a) and boss.Deadline==deadline)
enemies.Damage(a,20);assert(boss.HealthLabel.Text=='310 / 330 HP' and boss.WaveLabel.Text=='WAVE 5 · BOSS')
advance(deadline-clock+.01);advance(1.05)
assert(a.CurrentWave==4 and a.CurrentEnemy.WaveLabel.Text=='WAVE 4')
assert(b.CurrentWave==1 and b.CurrentEnemy==second and second.WaveLabel.Text=='WAVE 1')
local gui=a.CurrentEnemy.Model.PrimaryPart.HealthDisplay
assert(gui.Wave.Text=='WAVE 4' and gui.HealthBar.Fill==a.CurrentEnemy.HealthFill)
print('PASS: actual personal Wave 1->2->Boss 5->timeout Wave 4 labels, independent second player, timer/HP/health bar/reset deadline preserved')
''')

scenarios['owner-display-world-stop-and-restart']=('',r'''
local a=claim(p1,1);local portrait=a.Island.OwnerAvatar
local hub=workspace.IdleHeroSimulatorWorld.Hub;local oldSpawn=hub.PlayerSpawn
islandService.Stop()
assert(portrait.destroyed and oldSpawn.destroyed and not registry.GetStored(p1))
islandService.Start();local fresh=claim(p1,1)
assert(fresh and fresh.Island.OwnerAvatar~=portrait)
assert(fresh.Island.OwnerAvatar:GetAttribute('OwnerUserId')==p1.UserId)
assert(alive('BillboardGui','OwnerAvatar')==1 and alive('Attachment','HubTitleAnchor')==1)
print('PASS: world-stop destroys owner display/context/spawn; restart/reclaim creates exactly one fresh portrait and centered title anchor')
''')

if __name__ == '__main__':
    run_scenarios(scenarios)
