-- New map creation dialog: inline W/H/Dir spinner with white background,
-- map preview rectangle, and bidirectional warp connection.

local NewMap = {}
local NewMapDialog = require("mods.map_editor.renderer.new_map_dialog")

function NewMap.newMapDialog(self)
  self._newMapState = {
    editField = "w", width = 10, height = 10, dir = "N", showPreview = true
  }
end

function NewMap._newMapConfirm(self)
  local state = self._newMapState
  if not state then return end
  local newId = self.mapId .. "_EXT"
  local data = self.data
  data.maps = data.maps or {}
  local border = self.def.borderBlock or 0
  local blocks = {}
  for i = 1, state.width * state.height do blocks[i] = border end
  local newDef = {
    id = newId, width = state.width, height = state.height,
    blocks = blocks, borderBlock = border,
    warps = {}, objects = {}, signs = {},
    tileset = self.def.tileset, palette = self.def.palette,
  }
  data.maps[newId] = newDef

  local cx, cy
  if state.dir == "N" then cx = self.def.width; cy = 0
  elseif state.dir == "S" then cx = self.def.width; cy = self.def.height * 2 - 1
  elseif state.dir == "E" then cx = self.def.width * 2 - 1; cy = self.def.height
  else cx = 0; cy = self.def.height end
  table.insert(self.def.warps, { x = cx, y = cy, destMap = newId, destWarp = 1 })

  local rx, ry
  if state.dir == "N" then rx = state.width; ry = state.height * 2 - 1
  elseif state.dir == "S" then rx = state.width; ry = 0
  elseif state.dir == "E" then rx = 0; ry = state.height
  else rx = state.width * 2 - 1; ry = state.height end
  table.insert(newDef.warps, { x = rx, y = ry, destMap = self.mapId, destWarp = #self.def.warps })

  self._newMapState = nil
  self.mapChanged = true
  self.mod.log:info("Created new map %s (%dx%d) connected %s", newId, state.width, state.height, state.dir)
end

function NewMap.drawNewMapDialog(self)
  NewMapDialog.draw(self)
end

return NewMap
