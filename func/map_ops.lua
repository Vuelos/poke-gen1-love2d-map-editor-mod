-- Map editing operations: paint, revert, flood fill, expand, undo/redo,
-- and original-state snapshots.

local Fill = require("mods.map_editor.func.fill")
local Common = require("mods.map_editor.func.common")
local CELL_PX = Common.CELL_PX
local BLOCK_PX = Common.BLOCK_PX

local MapOps = {}

-- Opposite connection direction for reciprocal fixing.
local BACK = { north = "south", south = "north", east = "west", west = "east" }

-- Keeps the connection graph consistent after this map's connection offsets
-- moved (expansion).  The engine places the connected map's strip at
-- `conn.offset * 32` and lands crossings at `cur - conn.offset * 2`, and the
-- vanilla reciprocal invariant is `back.offset == -offset` -- so when this
-- map's offsets shift, every connected map's return connection must mirror
-- the new value or a round-trip seam crossing lands at the wrong cell.
-- Applies the fix to the live data and persists it as a connections-only
-- patch on each affected map so it survives a reload.
function MapOps.reconcileReciprocalConnections(self)
  local data = self.data
  if not data or not data.maps then return end
  local def = self.def
  local changed = {}
  for dir, conn in pairs(def.connections or {}) do
    local back = BACK[dir]
    if back and conn and conn.map then
      local other = data.maps[conn.map]
      if other and other ~= def then
        local r = other.connections and other.connections[back]
        if r and r.map == self.mapId then
          local want = -(conn.offset or 0)
          if (r.offset or 0) ~= want then
            r.offset = want
            changed[conn.map] = true
          end
        end
      end
    end
  end
  if next(changed) then
    local Save = require("mods.map_editor.func.save")
    for otherId in pairs(changed) do
      Save.updatePatchField(self.mod, otherId, "connections",
        Common.deepCopy(data.maps[otherId].connections))
    end
  end
end

function MapOps.expandMap(self, needL, needR, needT, needB)
  if needL == 0 and needR == 0 and needT == 0 and needB == 0 then return end
  local oldW = self.def.width
  local oldH = self.def.height
  local newW = oldW + needL + needR
  local newH = oldH + needT + needB
  local border = self.def.borderBlock or 0

  local newBlocks = {}
  for by = 0, newH - 1 do
    for bx = 0, newW - 1 do
      local obx = bx - needL
      local oby = by - needT
      local idx = by * newW + bx + 1
      if obx >= 0 and obx < oldW and oby >= 0 and oby < oldH then
        newBlocks[idx] = self.def.blocks[oby * oldW + obx + 1]
      else
        newBlocks[idx] = border
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
      c.north.offset = (c.north.offset or 0) + cellShiftX / 2
    end

    if c.south then
      c.south.offset = (c.south.offset or 0) + cellShiftX / 2
    end

    if c.east then
      c.east.offset = (c.east.offset or 0) + cellShiftY / 2
    end

    if c.west then
      c.west.offset = (c.west.offset or 0) + cellShiftY / 2
    end
  end

  self.def.width = newW
  self.def.height = newH
  self.def.blocks = newBlocks
  self.mapW = newW * BLOCK_PX
  self.mapH = newH * BLOCK_PX
  -- Track how far the original content was shifted so revertBlock can map
  -- current block coords back to the persisted snapshot.
  self.expandShiftL = (self.expandShiftL or 0) + needL
  self.expandShiftT = (self.expandShiftT or 0) + needT
  self.cursorBx = self.cursorBx + needL * 2
  self.cursorBy = self.cursorBy + needT * 2
  self.mapChanged = true
end

-- Resolves which map a MAP-mode tile operation anchored at world-cell
-- (cellX, cellY) edits.  The edited map wins inside its own body; a cell
-- inside a laid-out neighbor's body targets that map; any other cell falls
-- back to the edited map (auto-expansion when painting past an edge).
-- Returns mapId (nil = the edited map), the def, and the map's world-pixel
-- origin for local block-coordinate math.
local function paintTarget(self, cellX, cellY)
  local px = cellX * CELL_PX
  local py = cellY * CELL_PX
  local w = self.def.width * BLOCK_PX
  local h = self.def.height * BLOCK_PX
  if px >= 0 and px < w and py >= 0 and py < h then
    return nil, self.def, 0, 0
  end
  for _, nb in ipairs(self.neighbors or {}) do
    local nw = nb.def.width * BLOCK_PX
    local nh = nb.def.height * BLOCK_PX
    if px >= nb.ox and px < nb.ox + nw and py >= nb.oy and py < nb.oy + nh then
      return nb.id, nb.def, nb.ox, nb.oy
    end
  end
  return nil, self.def, 0, 0
end

-- Renders the affected map (the edited one, or a connected map) after a
-- block change.
local function rebuildFor(self, mapId)
  if mapId then
    local m = self.neighborMaps and self.neighborMaps[mapId]
    if m and m.renderer then m.renderer:rebuild() end
  else
    self.map.renderer:rebuild()
  end
end

function MapOps.paintBlock(self)
  local bs = self.brushSize
  local mapId, def, ox, oy = paintTarget(self, self.cursorBx, self.cursorBy)
  local px0 = self.cursorBx * CELL_PX
  local py0 = self.cursorBy * CELL_PX
  local bx0 = math.floor((px0 - ox) / BLOCK_PX)
  local by0 = math.floor((py0 - oy) / BLOCK_PX)
  local bx1 = math.floor((px0 + (bs - 1) * CELL_PX - ox) / BLOCK_PX)
  local by1 = math.floor((py0 + (bs - 1) * CELL_PX - oy) / BLOCK_PX)

  if mapId == nil then
    -- The edited map: auto-expand when painting past an edge.
    local needL = math.max(0, -bx0)
    local needR = math.max(0, bx1 + 1 - def.width)
    local needT = math.max(0, -by0)
    local needB = math.max(0, by1 + 1 - def.height)

    if self.undo then self.undo:capture(def, self.expandShiftL, self.expandShiftT) end
    if needL > 0 or needR > 0 or needT > 0 or needB > 0 then
      self:expandMap(needL, needR, needT, needB)
      bx0 = math.floor(self.cursorBx / 2)
      by0 = math.floor(self.cursorBy / 2)
      bx1 = math.floor((self.cursorBx + bs - 1) / 2)
      by1 = math.floor((self.cursorBy + bs - 1) / 2)
    end
  else
    -- A connected map: paint within its existing bounds (a map is never
    -- expanded from across a seam), so a brush straddling the seam clips.
    bx0 = math.max(0, bx0); by0 = math.max(0, by0)
    bx1 = math.min(bx1, def.width - 1); by1 = math.min(by1, def.height - 1)
    if bx0 > bx1 or by0 > by1 then return end
    if self.undo then self.undo:capture(def, nil, nil, mapId) end
    self.neighborDirty[mapId] = true
  end

  local w = def.width
  for by = by0, by1 do
    for bx = bx0, bx1 do
      def.blocks[by * w + bx + 1] = self.selectedBlock
    end
  end
  self.mapChanged = true
  rebuildFor(self, mapId)
end

function MapOps.revertBlock(self)
  local mapId, def, ox, oy = paintTarget(self, self.cursorBx, self.cursorBy)
  local bx = math.floor((self.cursorBx * CELL_PX - ox) / BLOCK_PX)
  local by = math.floor((self.cursorBy * CELL_PX - oy) / BLOCK_PX)

  if mapId == nil then
    local obx = bx - (self.expandShiftL or 0)
    local oby = by - (self.expandShiftT or 0)
    if obx >= 0 and obx < self.originalWidth and oby >= 0 and oby < self.originalHeight then
      local idx = by * def.width + bx + 1
      if idx >= 1 and idx <= #def.blocks then
        if self.undo then self.undo:capture(def, self.expandShiftL, self.expandShiftT) end
        def.blocks[idx] = self.originalBlocks[oby * self.originalWidth + obx + 1]
        self.mapChanged = true
        self.map.renderer:rebuild()
      end
    end
    return
  end

  local orig = self.neighborOriginals and self.neighborOriginals[mapId]
  if not orig then return end
  local idx = by * def.width + bx + 1
  if bx >= 0 and bx < def.width and by >= 0 and by < def.height
     and idx >= 1 and idx <= #def.blocks then
    if self.undo then self.undo:capture(def, nil, nil, mapId) end
    def.blocks[idx] = orig.blocks[idx]
    self.mapChanged = true
    self.neighborDirty[mapId] = true
    rebuildFor(self, mapId)
  end
end

function MapOps.floodFill(self)
  local mapId, def, ox, oy = paintTarget(self, self.cursorBx, self.cursorBy)
  local bx = math.floor((self.cursorBx * CELL_PX - ox) / BLOCK_PX)
  local by = math.floor((self.cursorBy * CELL_PX - oy) / BLOCK_PX)
  if self.undo then
    if mapId == nil then
      self.undo:capture(def, self.expandShiftL, self.expandShiftT)
    else
      self.undo:capture(def, nil, nil, mapId)
    end
  end
  local changed = Fill.flood(def, bx, by, self.selectedBlock)
  if changed > 0 then
    self.mapChanged = true
    if mapId ~= nil then self.neighborDirty[mapId] = true end
    rebuildFor(self, mapId)
  end
end

function MapOps.selectCursorBlock(self)
  local mapId, def, ox, oy = paintTarget(self, self.cursorBx, self.cursorBy)
  local bx = math.floor((self.cursorBx * CELL_PX - ox) / BLOCK_PX)
  local by = math.floor((self.cursorBy * CELL_PX - oy) / BLOCK_PX)
  if bx < 0 or by < 0 or bx >= def.width or by >= def.height then return end
  local b = def.blocks[by * def.width + bx + 1]
  if b then self.selectedBlock = b end
end

-- Rounds the cursor down to the even cell of the block it currently sits
-- in.  MAP mode moves and paints in whole 2-cell blocks, so a cursor left
-- on an odd cell by ENT/ENC must snap back before MAP work resumes or the
-- cursor highlight and the block grid disagree.
function MapOps.snapCursorToBlock(self)
  self.cursorBx = self.cursorBx - (self.cursorBx % 2)
  self.cursorBy = self.cursorBy - (self.cursorBy % 2)
end

function MapOps.restoreSnapshot(self, kind)
  -- Peek the target stack to find which map the next step belongs to:
  -- nil means the edited map, otherwise a connected map painted across a
  -- seam.  Each step must be re-applied to the def it captured.
  local stack = self.undo:stack(kind == "redo" and "redo" or "undo")
  local top = stack and stack[#stack]
  local mapId = top and top.mapId
  local def = self.def
  if mapId then
    local m = self.neighborMaps and self.neighborMaps[mapId]
    if not m or not m.def then return end
    def = m.def
  end
  local shiftL, shiftT = self.expandShiftL, self.expandShiftT
  if mapId then shiftL, shiftT = nil, nil end
  local snap = kind == "redo"
    and self.undo:redo(def, shiftL, shiftT, mapId)
    or self.undo:undo(def, shiftL, shiftT, mapId)
  if not snap then return end
  if snap.shiftL ~= nil then self.expandShiftL = snap.shiftL end
  if snap.shiftT ~= nil then self.expandShiftT = snap.shiftT end
  self.mapW = self.def.width * BLOCK_PX
  self.mapH = self.def.height * BLOCK_PX
  if mapId then
    local m = self.neighborMaps[mapId]
    if m and m.renderer then m.renderer:rebuild() end
  else
    self:reloadMap()
    self.map.renderer:rebuild()
    -- The undo may have restored a different connection layout; re-derive
    -- the neighbor set and re-capture its originals.
    self:rebuildNeighbors()
  end
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
  self.originalConnections = Common.deepCopy(self.def.connections or {})
  -- Connections on OTHER maps that point back to this one: the expansion
  -- reconciliation rewrites their return offsets, so snapshot them too to
  -- restore on unsaved exit.
  self.originalRecipConnections = {}
  if self.data and self.data.maps then
    for otherId, otherDef in pairs(self.data.maps) do
      if otherId ~= self.mapId then
        for _, conn in pairs(otherDef.connections or {}) do
          if conn.map == self.mapId then
            self.originalRecipConnections[otherId] = Common.deepCopy(otherDef.connections)
            break
          end
        end
      end
    end
  end
  self.originalEncounters = Common.deepCopy(
    self.data and self.data.encounters and self.data.encounters[self.mapId]
  )
  self.expandShiftL = 0
  self.expandShiftT = 0
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
