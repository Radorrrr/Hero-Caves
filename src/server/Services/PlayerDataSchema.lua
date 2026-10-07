local Shared = game:GetService("ReplicatedStorage").Shared
local Heroes = require(Shared.HeroConfig)
local Config = require(Shared.GameConfig)
local Schema = {Version = 1}
local function integer(value, default, maximum)
 if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value < 0 then return default end
 return math.clamp(math.floor(value), default, maximum)
end
function Schema.Reconcile(raw)
 if raw ~= nil and type(raw) ~= "table" then return nil, "InvalidRoot" end
 raw = raw or {}
 local version = raw.SchemaVersion
 if version ~= nil and (type(version) ~= "number" or version < 0 or version % 1 ~= 0 or version > Schema.Version) then return nil, "UnsupportedSchema" end
 -- Version 0 (unversioned/partial data) migrates by reconciling known fields.
 local data = {SchemaVersion = Schema.Version, Gold = integer(raw.Gold, 0, Config.Economy.MaxGold),
  Wave = integer(raw.Wave, 1, Config.Persistence.MaxSavedWave), Heroes = {}}
 local input = type(raw.Heroes) == "table" and raw.Heroes or {}
 for _, id in Heroes.HeroOrder do
  local definition = Heroes[id]
  local saved = type(input[id]) == "table" and input[id] or {}
  local owned = definition.OwnedByDefault or saved.Owned == true
  local hero = {Owned = owned, Level = owned and integer(saved.Level, 1, definition.MaxLevel) or 1, Upgrades = {}}
  local purchased = type(saved.PurchasedUpgrades) == "table" and saved.PurchasedUpgrades
   or (type(saved.Upgrades) == "table" and saved.Upgrades or {})
  local ids = {}
  for key, value in purchased do
   if type(value) == "string" then ids[value] = true elseif type(key) == "string" and value == true then ids[key] = true end
  end
  for _, upgrade in definition.Milestones or {} do
   if owned and hero.Level >= upgrade.Level and ids[upgrade.Id] then hero.Upgrades[upgrade.Id] = true end
  end
  data.Heroes[id] = hero
 end
 return data
end
function Schema.Defaults(testing)
 local data = Schema.Reconcile(nil)
 if testing then
  data.Gold = integer(Config.StudioTesting.StartingGold, 0, Config.Economy.MaxGold)
  for _, id in Heroes.HeroOrder do
   local hero = data.Heroes[id]
   hero.Owned = hero.Owned or Config.StudioTesting.StartingOwnedHeroes[id] == true
   hero.Level = hero.Owned and integer(Config.StudioTesting.StartingHeroLevels[id], 1, Heroes[id].MaxLevel) or 1
  end
 end
 return data
end
function Schema.Encode(data)
 local saved = {SchemaVersion = Schema.Version, Gold = data.Gold, Wave = data.Wave, Heroes = {}}
 for _, id in Heroes.HeroOrder do
  local hero = data.Heroes[id]
  local upgrades = {}
  for _, upgrade in Heroes[id].Milestones or {} do if hero.Upgrades[upgrade.Id] then table.insert(upgrades, upgrade.Id) end end
  saved.Heroes[id] = {Owned = hero.Owned, Level = hero.Level, PurchasedUpgrades = upgrades}
 end
 return saved
end
return Schema
