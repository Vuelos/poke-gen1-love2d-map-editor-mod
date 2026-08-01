-- Session management for the editor: persists patches for maps
-- that were edited while primary or as neighbors, and tracks
-- session state for unsaved exits.

local Save = require("mods.map_editor.func.save")
local Common = require("mods.map_editor.func.common")
local Snapshot = require("mods.map_editor.func.snapshot")

local EditorSession = {}

function EditorSession.persistSessionMaps(self)
  for mapId in pairs(self._sessionDirty or {}) do
    local def = self.data and self.data.maps and self.data.maps[mapId]
    local orig = self._sessionOriginals and self._sessionOriginals[mapId]
    if def and orig then
      local patch = Snapshot.diff(def, orig)
      if next(patch) then
        for key, value in pairs(patch) do
          Save.updatePatchField(self.mod, mapId, key, value)
        end
      end
      local currentEnc = self.data.encounters and self.data.encounters[mapId]
      local origEnc = self._sessionEncounters and self._sessionEncounters[mapId]
      if not Common.tablesEqual(currentEnc, origEnc) then
        if currentEnc then
          Save.saveEncounterPatch(self.mod, mapId, Common.deepCopy(currentEnc))
        else
          Save.removeEncounterPatch(self.mod, mapId)
        end
      end
    end
    local curDef = self.data and self.data.maps and self.data.maps[mapId]
    if curDef then
      self._sessionOriginals[mapId] = Snapshot.capture(curDef)
      self._sessionEncounters[mapId] = Common.deepCopy(
        self.data and self.data.encounters and self.data.encounters[mapId])
    end
    self._sessionDirty[mapId] = nil
  end
end

function EditorSession.persistNeighborPatches(self)
  for nbId in pairs(self.neighborDirty or {}) do
    local m = self.neighborMaps and self.neighborMaps[nbId]
    local orig = self.neighborOriginals and self.neighborOriginals[nbId]
    if m and m.def and orig then
      local patch = Snapshot.diff(m.def, orig)
      if next(patch) then
        for key, value in pairs(patch) do
          Save.updatePatchField(self.mod, nbId, key, value)
        end
      end
    end
  end
  self.neighborDirty = {}
end

return EditorSession