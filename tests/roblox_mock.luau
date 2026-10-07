-- Minimal deterministic Roblox API mock; not a Studio/physics/network emulator.
local localPlayer
local isStudio=true
local warnings={}
local function warn(message) table.insert(warnings,tostring(message)) end

local clock=0
local function time() return clock end
local vectorMt={}
local Vector3={}
vectorMt.__div=function(a,s) return Vector3.new(a.X/s,a.Y/s,a.Z/s) end
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMt) end
Vector3.zero=Vector3.new(0,0,0)
vectorMt.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vectorMt.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vectorMt.__mul=function(a,s) return Vector3.new(a.X*s,a.Y*s,a.Z*s) end
vectorMt.__index=function(a,k)
 if k=='Magnitude' then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
 if k=='Unit' then return a*(1/a.Magnitude) end
 if k=='Dot' then return function(v,b) return v.X*b.X+v.Y*b.Y+v.Z*b.Z end end
end
local function rotate(r,v)
 return Vector3.new(r[1]*v.X+r[2]*v.Y+r[3]*v.Z,r[4]*v.X+r[5]*v.Y+r[6]*v.Z,r[7]*v.X+r[8]*v.Y+r[9]*v.Z)
end
local cfMt={}
local CFrame={}
local function cf(p,r) return setmetatable({Position=p,R=r},cfMt) end
function CFrame.new(x,y,z)
 local p=type(x)=='table' and x or Vector3.new(x or 0,y or 0,z or 0)
 return cf(p,{1,0,0,0,1,0,0,0,1})
end
function CFrame.Angles(x,y,z)
 assert(y==0 and z==0)
 return cf(Vector3.zero,{1,0,0,0,math.cos(x),-math.sin(x),0,math.sin(x),math.cos(x)})
end
function CFrame.lookAt(p,t)
 local d=(t-p).Unit
 local right=Vector3.new(-d.Z,0,d.X).Unit
 local up=Vector3.new(right.Y*d.Z-right.Z*d.Y,right.Z*d.X-right.X*d.Z,right.X*d.Y-right.Y*d.X)
 return cf(p,{right.X,up.X,-d.X,right.Y,up.Y,-d.Y,right.Z,up.Z,-d.Z})
end
cfMt.__index=function(a,k)
 if k=='PointToObjectSpace' then return function(self,point)
  local v=point-self.Position;local r=self.R
  return Vector3.new(r[1]*v.X+r[4]*v.Y+r[7]*v.Z,r[2]*v.X+r[5]*v.Y+r[8]*v.Z,r[3]*v.X+r[6]*v.Y+r[9]*v.Z)
 end end
 if k=='UpVector' then return Vector3.new(a.R[2],a.R[5],a.R[8]) end
 if k=='LookVector' then return Vector3.new(-a.R[3],-a.R[6],-a.R[9]) end end
cfMt.__mul=function(a,b)
 local r={}
 for i=0,2 do for j=0,2 do local v=0; for k=0,2 do v+=a.R[i*3+k+1]*b.R[k*3+j+1] end; r[i*3+j+1]=v end end
 return cf(a.Position+rotate(a.R,b.Position),r)
end
local Color3={fromRGB=function(...) return {...} end}
local UDim2={fromScale=function(...) return {...} end,fromOffset=function(...) return {...} end,new=function(...) return {...} end}
local TweenInfo={new=function(t) return {Duration=t} end}
local Enum={PartType={Ball='Ball'},Material={SmoothPlastic='SmoothPlastic',Metal='Metal'},Font={GothamBold='GothamBold'},EasingStyle={Sine='Sine'},EasingDirection={InOut='InOut'}}
local objects={}
local Instance={}

local function signal()
 local s={Listeners={}}
 function s:Connect(fn)
  local c={fn=fn,connected=true}
  function c:Disconnect() self.connected=false end
  table.insert(self.Listeners,c); return c
 end
 function s:Fire(...) for _,c in self.Listeners do if c.connected then c.fn(...) end end end
 return s
end
local instanceMt={}


instanceMt.__index=function(o,k)
 if k=='CFrame' and not o.Data.CFrame then return CFrame.new(o.Data.Position or Vector3.zero) end
 if k=='IsA' then return function(self,class)
  return self.ClassName==class or (class=='BasePart' and (self.ClassName=='Part' or self.ClassName=='SpawnLocation'))
 end end
 if k=='IsDescendantOf' then return function(self,parent)
  local current=self.Parent;while current do if current==parent then return true end;current=current.Parent end;return false
 end end
 if k=='GetDescendants' then return function(self)
  local list={};for _,obj in objects do if obj:IsDescendantOf(self) then table.insert(list,obj) end end;return list
 end end
 if k=='GetFullName' then return function(self) return self.Name or self.ClassName end end

 if k=='FindFirstAncestorOfClass' then return function(self,class)
  local obj=self.Parent;while obj do if obj.ClassName==class then return obj end;obj=obj.Parent end
 end end
 if k=='FindFirstChildOfClass' then return function(self,class)
  for _,obj in objects do if obj.Parent==self and obj.ClassName==class then return obj end end
 end end
 if k=='GetChildren' then return function(self)
  local list={};for _,obj in objects do if obj.Parent==self then table.insert(list,obj) end end;return list
 end end
 if k=='PivotTo' then return function(self,frame)
  self.Pivot=frame;local root=self:FindFirstChild('HumanoidRootPart');if root then root.CFrame=frame end
 end end

 if k=='Parent' then return o.Data.Parent end
 if k=='Position' then return o.Data.CFrame and o.Data.CFrame.Position or o.Data.Position or Vector3.zero end
 
 if k=='SetAttribute' then return function(self,name,v)
  local old=self.attrs[name]; self.attrs[name]=v
  if old~=v then
 if self.AttributeSignals[name] then self.AttributeSignals[name]:Fire() end
 self.AttributeChanged:Fire(name)
 end
 end end
 if k=='GetAttribute' then return function(self,name) return self.attrs[name] end end
 if k=='GetAttributeChangedSignal' then return function(self,name)
  if not self.AttributeSignals[name] then self.AttributeSignals[name]=signal() end
  return self.AttributeSignals[name]
 end end
 if k=='FindFirstChild' or k=='WaitForChild' then return function(self,name)
  if self.Data[name] then return self.Data[name] end
  for _,o in objects do if o.Parent==self and o.Name==name then return o end end
  if k=='WaitForChild' then error('missing child '..name) end
 end end

 if k=='Destroy' then return function(self)
  for _,child in objects do if child.Parent==self then child:Destroy() end end
  self.Data.Parent=nil; self.destroyed=true
 end end
 if o.Data[k] ~= nil then return o.Data[k] end
 for _,child in objects do if child.Parent==o and child.Name==k then return child end end
 return nil
end
instanceMt.__newindex=function(o,k,v) o.Data[k]=v end
-- Roblox copies Lua tables across BindableEvent arguments; Instances retain identity.
-- Preserve mock userdata (Instance/Vector3/CFrame metatables), copy plain tables.
local function copyBindableValue(value, seen)
 if type(value)~='table' or getmetatable(value)~=nil then return value end
 if seen[value] then return seen[value] end
 local copy={};seen[value]=copy
 for key,item in value do copy[copyBindableValue(key,seen)]=copyBindableValue(item,seen) end
 return copy
end
function Instance.new(class)
 
 local o=setmetatable({Data={ClassName=class},attrs={},AttributeSignals={},destroyed=false},instanceMt)
 if class=='BindableEvent' then
  o.Event=signal(); function o:Fire(...)
   local args=copyBindableValue(table.pack(...),{})
   self.Event:Fire(table.unpack(args,1,args.n))
  end
 elseif class=='RemoteEvent' then
  o.OnServerEvent=signal(); o.OnClientEvent=signal(); o.Responses={}; o.Requests={}
  local connectClient=o.OnClientEvent.Connect
  function o.OnClientEvent:Connect(fn)
   local connection=connectClient(self,fn);connection.Player=localPlayer;return connection
  end
  function o:FireClient(player,...)
   table.insert(self.Responses,{player,...})
   for _,connection in self.OnClientEvent.Listeners do
    if connection.connected and connection.Player==player then connection.fn(...) end
   end
  end
  function o:FireServer(...) table.insert(self.Requests,{...}); self.OnServerEvent:Fire(localPlayer,...) end
 elseif class=='ProximityPrompt' then o.Triggered=signal()
 elseif class=='TextButton' then o.Activated=signal() end

 o.AttributeChanged=signal()
 if class=='Part' or class=='SpawnLocation' then o.Touched=signal() end
 if class=='Player' then o.CharacterAdded=signal() end
 table.insert(objects,o)
 if class=='SpawnLocation' then local decal=Instance.new('Decal');decal.Name='SpawnTexture';decal.Transparency=0;decal.Parent=o end
 return o
end
local workspace=Instance.new('Workspace')
local listeners={}
local heartbeat={}
function heartbeat:Connect(fn)
 local c={connected=true,fn=fn}
 function c:Disconnect() self.connected=false end
 table.insert(listeners,c); return c
end
local tweens={}
local TweenService={}
function TweenService:GetValue(p,style,direction) return (1-math.cos(math.pi*p))/2 end
function TweenService:Create(o,info,goals)
 local completed=signal(); return {Completed=completed,Play=function() table.insert(tweens,{Object=o,Finish=clock+info.Duration,Goals=goals,Completed=completed}) end}
end
local modules={}

local shared={GameConfig='GameConfig',EnemyConfig='EnemyConfig',HeroConfig='HeroConfig',NumberFormatter='NumberFormatter'}
function shared:WaitForChild(n) assert(self[n],n); return self[n] end
local storage=Instance.new('ReplicatedStorage'); storage.Shared=shared
local players=Instance.new('Players')
players.PlayerAdded=signal(); players.PlayerRemoving=signal(); players.List={}
function players:GetPlayers() return table.clone(self.List) end
local function addPlayer(id,name)
 local p=Instance.new('Player'); p.UserId=id; p.Name=name; p.DisplayName=name; p.Parent=players
 table.insert(players.List,p); players.PlayerAdded:Fire(p); return p
end
local function removePlayer(p)
 players.PlayerRemoving:Fire(p)
 for i,v in players.List do if v==p then table.remove(players.List,i); break end end
 p.Parent=nil
end
local p1=addPlayer(101,'PlayerOne')
localPlayer=p1; players.LocalPlayer=p1; p1.IsLocal=true
local playerGui=Instance.new('PlayerGui'); playerGui.Name='PlayerGui'; playerGui.Parent=p1
local Vector2={new=function(...) return {...} end}
local UDim={new=function(...) return {...} end}
Enum.KeyCode={E='E'}
Enum.Material.Wood='Wood'; Enum.Material.Neon='Neon'; Enum.PartType.Block='Block'
Enum.Font.Gotham='Gotham'; Enum.TextXAlignment={Left='Left',Right='Right'}
Enum.AutomaticSize={Y='Y'}; Enum.ScrollingDirection={Y='Y'}; Enum.SortOrder={LayoutOrder='LayoutOrder'}

local services={CombatDebugState='CombatDebugState',CombatDebugService='CombatDebugService',GoldPopup='GoldPopup',CombatDebugPanel='CombatDebugPanel',EnemyService='EnemyService',WaveService='WaveService',CombatService='CombatService',HeroService='HeroService',EconomyService='EconomyService',ProgressionService='ProgressionService',Parent={ProgressionMath='ProgressionMath',UpgradeEffects='UpgradeEffects',Heroes={KnightRig='KnightRig',RangedRig='RangedRig'}}}
local game={}
function game:GetService(n)
 if n=='ReplicatedStorage' then return storage end
 if n=='Players' then return players end
 if n=='RunService' then return {Heartbeat=heartbeat,IsStudio=function() return isStudio end} end
 if n=='TweenService' then return TweenService end
 error(n)
end
local function require(n) assert(modules[n],n); return modules[n] end
local function alive(class,name)
 local count=0
 for _,o in objects do if not o.destroyed and o.ClassName==class and (not name or o.Name==name) then count+=1 end end
 return count
end
local function connected()
 local n=0; for _,c in listeners do if c.connected then n+=1 end end; return n
end
local function tick(dt)
 clock+=dt
 for _,c in listeners do if c.connected then c.fn() end end
 for i=#tweens,1,-1 do
  local t=tweens[i]
  if clock>=t.Finish then
   if not t.Object.destroyed then for k,v in t.Goals do t.Object[k]=v end end
   table.remove(tweens,i)
  end
 end
end
local function advance(t)
 local target=clock+t
 while clock < target-0.000001 do tick(math.min(0.01,target-clock)) end
end

local delayed={}
local task={spawn=function(fn,...) fn(...) end,delay=function(_,fn) table.insert(delayed,fn) end}
function players:GetPlayerFromCharacter(character)
 for _,p in self.List do if p.Character==character then return p end end
end
shared.WorldConfig='WorldConfig'
for _,name in {'CombatContexts','CombatContextService','IslandService','HeroShopService','HeroShopPanel'} do services[name]=name end
