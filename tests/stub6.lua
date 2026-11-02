-- stubs for the fun counters (on top of stub3/4/5)
ITEMINFO = {}
C_Item.GetItemInfoInstant = function(id) local i = ITEMINFO[id] if i then return id, "Trade Goods", "x", "", 0, i[1], i[2] end end
FALLING = false
IsFalling = function() return FALLING end
FISHING = false
IsFishingLoot = function() return FISHING end
GetLootSlotInfo = function(slot) local l = LOOT[slot] return "icon", "item", l and l.qty or 1 end
MAPPOS = nil
C_Map = {
  GetBestMapForUnit = function() return MAPPOS and 1429 or nil end,
  GetPlayerMapPosition = function() return MAPPOS and { x = 0.5, y = 0.5 } or nil end,
  GetWorldPosFromMapPos = function() return 0, { x = MAPPOS.x, y = MAPPOS.y } end,
}
UnitOnTaxi = function() return false end
local oldLevel = UnitLevel
UnitLevel = function(u) if u ~= "player" and UNITS[u] and UNITS[u].level then return UNITS[u].level end return oldLevel(u) end
UnitIsPlayer = function(u) return UNITS[u] and UNITS[u].player or false end
local oldCT = UnitCreatureType
UnitCreatureType = function(u) if UNITS[u] and UNITS[u].ctype then return UNITS[u].ctype end return oldCT(u) end
SOUNDS = {}
PlaySoundFile = function(f) table.insert(SOUNDS, f) return false end
PlaySound = function(id) table.insert(SOUNDS, id) return true end
