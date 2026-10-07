local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local Schema = require(script.Parent.PlayerDataSchema)
local Data = {}
local ready = Instance.new("BindableEvent")
Data.Ready = ready.Event
local profiles = {}
local initializers = {}
-- Synchronous callbacks finish constructing gameplay state before load publication.
function Data.RegisterInitializer(callback) table.insert(initializers, callback) end
local store, started, closing = nil, false, false
local function diagnostic(player, message)
 warn("[PlayerData] " .. player.Name .. ": " .. message)
end
function Data.GetProfile(player) return profiles[player] end
function Data.IsReady(player)
 local profile = profiles[player]
 return profile ~= nil and profile.Ready and not profile.Closing and player.Parent == Players
end
function Data.MarkDirty(player)
 local profile = profiles[player]
 if profile and profile.Ready and not profile.Closing then profile.Revision += 1 end
end
function Data.GetWave(player)
 local profile = profiles[player]
 return profile and profile.Data and profile.Data.Wave or 1
end
function Data.SetWave(player, wave)
 if not Data.IsReady(player) then return false end
 local profile = profiles[player]
 local value = math.clamp(wave, 1, Config.Persistence.MaxSavedWave)
 if value ~= profile.Data.Wave then profile.Data.Wave = value; Data.MarkDirty(player) end
 return true
end
local function fail(player, profile, reason)
	profile.Ready = false
	profile.Loading = false
 player:SetAttribute("DataReady", false)
 player:SetAttribute("DataStatus", reason)
 diagnostic(player, reason .. "; no default-data overwrite permitted")
 if player.Parent == Players then player:Kick("Your data could not be safely loaded or saved. Please rejoin. (" .. reason .. ")") end
 if profile.Closing or player.Parent ~= Players then profiles[player] = nil end
end
local function update(profile, callback)
 local policy = Config.Persistence
 for attempt = 1, policy.MaxAttempts do
  if closing and os.clock() >= profile.Deadline then return false, "ShutdownDeadline" end
  local success, result = pcall(function() return store:UpdateAsync(profile.Key, callback) end)
  if success then return true, result end
  diagnostic(profile.Player, "DataStore attempt " .. attempt .. " failed: " .. tostring(result))
  if attempt < policy.MaxAttempts then task.wait(policy.RetryDelay * attempt) end
 end
 return false, "DataStoreUnavailable"
end
function Data.Save(player, release)
 local profile = profiles[player]
 if not profile or not profile.Data or not profile.Ready then return false, "NotReady" end
 if release then profile.Closing = true; player:SetAttribute("DataReady", false) end
 if profile.Saving then return false, "Busy" end
 profile.Saving = true
 local revision = profile.Revision
 local snapshot = Schema.Encode(profile.Data)
 local success, result = true, snapshot
 if store then
  success, result = update(profile, function(current)
   if type(current) ~= "table" or type(current.Session) ~= "table" or current.Session.Token ~= profile.Token then return nil end
   local output = {SchemaVersion = snapshot.SchemaVersion, Gold = snapshot.Gold, Wave = snapshot.Wave, Heroes = snapshot.Heroes}
   output.Session = not release and {Token = profile.Token, Expires = os.time() + Config.Persistence.SessionLeaseSeconds} or nil
   return output
  end)
 end
 profile.Saving = false
 if success and result ~= nil then
  profile.SavedRevision = revision
  profile.LastSaved = snapshot
  profile.RenewAt = os.time() + Config.Persistence.SessionLeaseSeconds / 2
  player:SetAttribute("LastSaveStatus", "Saved")
 else
  player:SetAttribute("LastSaveStatus", "Failed")
  diagnostic(player, "Save failed; dirty state retained")
  if success and result == nil then fail(player, profile, "SessionLost") end
 end
 if profile.Closing then
  if not release and success and result ~= nil then return Data.Save(player, true) end
  profiles[player] = nil
 end
 return success and result ~= nil, result
end
local function load(player)
 if profiles[player] or closing then return end
 local profile = {Player = player, Key = "Player_" .. player.UserId, Ready = false,
  Revision = 0, SavedRevision = 0, Deadline = math.huge, Loading = true}
 profiles[player] = profile
 player:SetAttribute("DataReady", false)
 player:SetAttribute("DataStatus", "Loading")
 local testing = RunService:IsStudio() and Config.StudioTesting.Enabled
 if not store then profile.Data = Schema.Defaults(testing)
 else
  profile.Token = game:GetService("HttpService"):GenerateGUID(false)
  local rejected
  local success, result = update(profile, function(current)
   rejected = nil
   local session = type(current) == "table" and current.Session
   if type(session) == "table" and session.Token ~= profile.Token and type(session.Expires) == "number" and session.Expires > os.time() then
    rejected = "SessionLocked"; return nil
   end
   local data, reason = Schema.Reconcile(current)
   if not data then rejected = reason; return nil end
   if current == nil then data = Schema.Defaults(testing) end
   local output = Schema.Encode(data)
   output.Session = {Token = profile.Token, Expires = os.time() + Config.Persistence.SessionLeaseSeconds}
   return output
  end)
  if not success or not result then fail(player, profile, rejected or "LoadFailed"); return end
  profile.Data = Schema.Reconcile(result)
 end
 profile.Loading = false
 profile.Ready = true
 profile.RenewAt = os.time() + Config.Persistence.SessionLeaseSeconds / 2
 profile.NextSave = time() + Config.Persistence.AutosaveInterval + player.UserId % 15
 if player.Parent ~= Players or profile.Closing or closing then Data.Save(player, true); return end
 for _, initialize in initializers do initialize(player) end
 player:SetAttribute("DataStatus", store and "Persistent" or "StudioMemory")
 player:SetAttribute("DataReady", true)
 ready:Fire(player) -- Player Instance only: never pass a profile table across BindableEvents.
end
function Data.Start()
 if started then return end
 started = true
 local policy = Config.Persistence
 assert(policy.AutosaveInterval >= 60 and policy.MaxAttempts >= 1 and policy.MaxAttempts <= 5)
 assert(policy.SessionLeaseSeconds > policy.AutosaveInterval * 2 and policy.RetryDelay >= 0)
 if not RunService:IsStudio() or policy.StudioMode == "DataStore" then
  local namespace = not RunService:IsStudio() and policy.DataStoreName
   or (Config.StudioTesting.Enabled and policy.StudioDebugDataStoreName or policy.StudioDataStoreName)
  assert(namespace ~= "" and (not RunService:IsStudio() or namespace ~= policy.DataStoreName), "Studio namespace must be separate")
  local success, result = pcall(function() return game:GetService("DataStoreService"):GetDataStore(namespace) end)
  if success then store = result else
   -- A failing adapter must still fail load; never fall back to writable default data.
   store = {UpdateAsync = function() error(result) end}
  end
 end
 Players.PlayerAdded:Connect(function(player) task.spawn(load, player) end)
 Players.PlayerRemoving:Connect(function(player)
  local profile = profiles[player]
  if profile and profile.Ready then Data.Save(player, true) end
  if profile and not profile.Ready then
   if profile.Loading then profile.Closing = true else profiles[player] = nil end
  end
 end)
 if store then
  local nextCheck = 0
  RunService.Heartbeat:Connect(function()
   if closing or time() < nextCheck then return end
   nextCheck = time() + 1
   for player, profile in profiles do
    if Data.IsReady(player) and time() >= profile.NextSave and not profile.Saving then
     profile.NextSave = time() + policy.AutosaveInterval + player.UserId % 15
     if profile.Revision ~= profile.SavedRevision or os.time() >= profile.RenewAt then task.spawn(Data.Save, player, false) end
    end
   end
  end)
 end
 game:BindToClose(function()
  closing = true
  local pending = 0
  local deadline = os.clock() + 25
  for player, profile in profiles do
   profile.Deadline = deadline
   if profile.Ready then
    pending += 1
    task.spawn(function() Data.Save(player, true); pending -= 1 end)
   end
  end
  while os.clock() < deadline do
   local saving = false
   for _, profile in profiles do if profile.Saving or profile.Loading then saving = true; break end end
   if pending == 0 and not saving then break end
   task.wait(0.1)
  end
 end)
 for _, player in Players:GetPlayers() do task.spawn(load, player) end
end
return Data
