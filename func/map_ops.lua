-- Map editing operations: paint, revert, flood fill, expand, undo/redo,
-- and original-state snapshots.

local Fill = require("mods.map_editor.func.fill")
local Common = require("mods.map_editor.func.common")
local CELL_PX = Common.CELL_PX
local BLOCK_PX = Common.BLOCK_PX

local MapOps = {}

function MapOps.expandMap(self, needL, needR, needT, needB)
  if needL == 0 and needR == 0 and needT == 0 and needB == 0 then return end
  local oldW = self.def.width
  local oldH = self.def.height
  local newW = oldW + needL + needR
  local newH = oldH + needT + needB
  local border = self.def.borderBlock or 0

  local newBlocks = {}
  local newOrig = {}
  for by = 0, newH - 1 do
    for bx = 0, newW - 1 do
      local obx = bx - needL
      local oby = by - needT
      local idx = by * newW + bx + 1
      if obx >= 0 and obx < oldW and oby >= 0 and oby < oldH then
        newBlocks[idx] = self.def.blocks[oby * oldW + obx + 1]
        newOrig[idx] = self.originalBlocks[oby * oldW + obx + 1]
      else
        newBlocks[idx] = border
        newOrig[idx] = border
      end
    end
  end

  local cellShiftX = needL * 2
  local cellShiftY = needT * 2
  if cellShiftX ~= 0 or cellShiftY ~= 0 then
    for _, w in ipairs(self.def.warps or {}) do
      w.x = w.x + cellShiftX; w.y = w.y + cellShiftY
    end
    for _, o in ipairs(self.def.objects or {}) do
      o.x = o.x + cellShiftX; o.y = o.y + cellShiftY
    end
    for _, s in ipairs(self.def.signs or {}) do
      s.x = s.x + cellShiftX; s.y = s.y + cellShiftY
    end
      
    local c = self.def.connections or {}

    if c.north then
      c.north.offset = (c.north.offset or 0) + cellShiftX / 32
    end

    if c.south then
      c.south.offset = (c.south.offset or 0) + cellShiftX / 32
    end

    if c.east then
      c.east.offset = (c.east.offset or 0) + cellShiftY / 32
    end

    if c.west then
      c.west.offset = (c.west.offset or 0) + cellShiftY / 32
    end
  end

  self.def.width = newW
  self.def.height = newH
  self.def.blocks = newBlocks
  self.originalBlocks = newOrig
  self.mapW = newW * BLOCK_PX
  self.mapH = newH * BLOCK_PX
  self.cursorBx = self.cursorBx + needL * 2
  self.cursorBy = self.cursorBy + needT * 2
  self.mapChanged = true
end

function MapOps.paintBlock(self)
  local bs = self.brushSize
  local bx0 = math.floor(self.cursorBx / 2)
  local by0 = math.floor(self.cursorBy / 2)
  local bx1 = math.floor((self.cursorBx + bs - 1) / 2)
  local by1 = math.floor((self.cursorBy + bs - 1) / 2)

  local needL = math.max(0, -bx0)
  local needR = math.max(0, bx1 + 1 - self.def.width)
  local needT = math.max(0, -by0)
  local needB = math.max(0, by1 + 1 - self.def.height)

  if self.undo then self.undo:capture(self.def) end
  if needL > 0 or needR > 0 or needT > 0 or needB > 0 then
    self:expandMap(needL, needR, needT, needB)
    bx0 = math.floor(self.cursorBx / 2)
    by0 = math.floor(self.cursorBy / 2)
    bx1 = math.floor((self.cursorBx + bs - 1) / 2)
    by1 = math.floor((self.cursorBy + bs - 1) / 2)
  end

  local w = self.def.width
  for by = by0, by1 do
    for bx = bx0, bx1 do
      self.def.blocks[by * w + bx + 1] = self.selectedBlock
    end
  end
  self.mapChanged = true
  self.map.renderer:rebuild()
end

function MapOps.revertBlock(self)
  local bx = math.floor(self.cursorBx / 2)
  local by = math.floor(self.cursorBy / 2)
  local idx = by * self.def.width + bx + 1
  if idx >= 1 and idx <= #self.originalBlocks then
    if self.undo then self.undo:capture(self.def) end
    self.def.blocks[idx] = self.originalBlocks[idx]
    self.mapChanged = true
    self.map.renderer:rebuild()
  end
end

function MapOps.floodFill(self)
  local bx = math.floor(self.cursorBx / 2)
  local by = math.floor(self.cursorBy / 2)
  if self.undo then self.undo:capture(self.def) end
  local changed = Fill.flood(self.def, bx, by, self.selectedBlock)
  if changed > 0 then
    self.mapChanged = true
    self.map.renderer:rebuild()
  end
end

function MapOps.selectCursorBlock(self)

  
end

function MapOps.restoreSnapshot(self, kind)
  local ok = kind == "redo" and self.undo:redo(self.def) or self.undo:undo(self.def)
  if not ok then return end
  self.mapW = self.def.width * BLOCK_PX
  self.mapH = self.def.height * BLOCK_PX
  self:reloadMap()
  self.map.renderer:rebuild()
  self.mapChanged = true
end

function MapOps.storeOriginal(self)
  self.originalBlocks = {}
  for i, v in ipairs(self.def.blocks) do self.originalBlocks[i] = v end
  self.originalWidth = self.def.width
  self.originalHeight = self.def.height
  self.originalWarps = Common.deepCopy(self.def.warps)
  self.originalObjects = Common.deepCopy(self.def.objects)
  self.originalSigns = Common.deepCopy(self.def.signs)
  self.originalBorder = self.def.borderBlock
  self.originalTextDefs = Common.deepCopy(self.def.textDefs or {})
  self.originalEncounters = Common.deepCopy(
    self.data and self.data.encounters and self.data.encounters[self.mapId]
  )
  self.paletteList = {}
  for i = 1, #self.tileset.blocks do self.paletteList[i] = i - 1 end
  self.spriteList = {}
  local sprites = self.data and self.data.sprites or {}
  local keys = {}
  for k in pairs(sprites) do table.insert(keys, k) end
  table.sort(keys)
  for _, id in ipairs(keys) do table.insert(self.spriteList, id) end
end

return MapOps
