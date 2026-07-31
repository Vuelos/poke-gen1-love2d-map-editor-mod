-- New map creation dialog: inline W/H/Dir spinner with white background,
-- map preview rectangle, and bidirectional warp connection.

local NewMap = {}

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
  local s = self._newMapState
  if not s then return end
  local vw, vh = require("src.render.Renderer"):uiSize()
  local boxX, boxY = 4, vh - 18
  local boxW, boxH = vw - 8, 10
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", boxX, boxY, boxW, boxH)
  local function drawField(label, value, active, offset)
    local full = label .. value
    if active then love.graphics.setColor(1, 0, 0, 1)
    else love.graphics.setColor(0, 0, 0, 1) end
    self.font.draw(full, boxX + 4 + offset, boxY + 1)
    return offset + self.font.width(full) + 8
  end
  local off = 0
  off = drawField("W:", tostring(s.width), s.editField == "w", off)
  off = drawField("H:", tostring(s.height), s.editField == "h", off)
  drawField("Dir:", s.dir, s.editField == "dir", off)
  love.graphics.setColor(1, 1, 1, 1)
end

return NewMap
