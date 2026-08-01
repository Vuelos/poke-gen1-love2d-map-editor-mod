-- Import/export and patch persistence for the editor screen.

local Save = require("mods.map_editor.func.save")
local Snapshot = require("mods.map_editor.func.snapshot")
local Common = require("mods.map_editor.func.common")
local TileRenderer = require("src.render.TileRenderer")
local MapLoader = require("src.world.MapLoader")

local EditorImportExport = {}

function EditorImportExport.savePatches(self)
  local patch = Snapshot.diff(self.def, self._originalSnapshot)
  Save.savePatch(self.mod, self.mapId, patch)
  self:reconcileReciprocalConnections(true)
  self:persistNeighborPatches()
  self:persistSessionMaps()
  local world = self.mod.world
  local shiftX = (self.expandShiftL or 0) * 2
  local shiftY = (self.expandShiftT or 0) * 2
  if world and world.rebaseMap
     and (patch.objects ~= nil or shiftX ~= 0 or shiftY ~= 0) then
    world:rebaseMap(self.mapId, shiftX, shiftY)
  end
  local invalidated = false
  if world and world.invalidateMap then
    invalidated = world:invalidateMap(self.mapId) ~= nil
  end
  if not invalidated then
    MapLoader.invalidate(self.mapId)
  end
  self.map = MapLoader.load(self.data, self.mapId)
  TileRenderer.tick(0)
  if self.def.textDefs and self.data then
    for _, td in ipairs(self.def.textDefs) do
      if not self.data.text_pointers[self.mapId] then
        self.data.text_pointers[self.mapId] = {}
      end
      self.data.text_pointers[self.mapId][td.const] = { text = td.key }
      self.data.text[td.key] = td.text
    end
  end
  local currentEnc = self.data and self.data.encounters and self.data.encounters[self.mapId]
  if not Common.tablesEqual(currentEnc, self.originalEncounters) then
    if currentEnc then
      Save.saveEncounterPatch(self.mod, self.mapId, Common.deepCopy(currentEnc))
    else
      Save.removeEncounterPatch(self.mod, self.mapId)
    end
  end
  self:rebuildNeighbors()
  self:storeOriginal(); self.mapChanged = false
  self.map.renderer:rebuild()
end

function EditorImportExport.exportPatches(self)
  local patch = Snapshot.diff(self.def, self._originalSnapshot)
  local lua = {"-- Map editor export for " .. self.mapId, "return {"}
  for key, value in pairs(patch) do
    if key == "blocks" then
      lua[#lua + 1] = "  blocks = {"
      local parts = {}
      for _, v in ipairs(value) do parts[#parts + 1] = tostring(v) end
      lua[#lua + 1] = "    " .. table.concat(parts, ", "); lua[#lua + 1] = "  },"
    elseif type(value) == "table" then
      local ok, enc = pcall(require("src.mods.Merge").encode, value)
      lua[#lua + 1] = "  " .. key .. " = " .. (ok and enc or "{}") .. ","
    else
      lua[#lua + 1] = "  " .. key .. " = " .. tostring(value) .. ","
    end
  end
  lua[#lua + 1] = "}"
  local text = table.concat(lua, "\n")
  local path = Save.writeFile(self.mapId, text)
  self.mod.log:info("Exported %s patches to %s", self.mapId, path)
end

function EditorImportExport.exportAllEdits(self)
  local path, err = Save.exportAll(self.mod)
  if path then
    self.mod.log:info("Exported all map edits to %s", path)
  else
    self.mod.log:warn("Export all map edits failed: %s", tostring(err))
  end
end

function EditorImportExport.importAllEdits(self)
  local edits, err = Save.importAll(self.mod)
  if not edits then
    self.mod.log:warn("Import all map edits failed: %s", tostring(err))
    return
  end
  local count = 0
  if edits.patches then
    count = count + Save.applyPatchesToData(edits.patches, self.data)
    for mapId, patch in pairs(edits.patches) do
      if patch.connections and self.data.connections then
        self.data.connections[mapId] = patch.connections
      end
    end
  end
  if edits.encounters then
    count = count + Save.applyEncounterPatches(edits.encounters, self.data)
  end
  if edits.connections then
    Save.applyConnectionPatches(edits.connections, self.data)
  end
  if MapLoader and MapLoader.invalidateAll then MapLoader.invalidateAll() end
  self:reloadMap()
  self:rebuildNeighbors()
  self.mapChanged = false
  self.mod.log:info("Imported map edits (%d maps) from map_edits/patches.lua", count)
end

return EditorImportExport