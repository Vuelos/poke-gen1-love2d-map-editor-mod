-- In-memory undo/redo system for the map editor.
-- Stores snapshots of map state (blocks, warps, objects, signs, dimensions)
-- before each edit operation.  Caller must invoke capture() BEFORE making
-- changes, then undo()/redo() to walk the stack.

local Undo = {}
Undo.__index = Undo

local MAX_UNDO = 50

-- Deep-copies a table value for snapshot storage.
local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = deepCopy(v) end
  return out
end

-- Creates a new undo stack.
function Undo.new()
  return setmetatable({
    _undoStack = {},
    _redoStack = {},
  }, Undo)
end

-- Captures a snapshot of the current map definition state.
-- Must be called BEFORE any mutation so the snapshot reflects the
-- pre-edit state.  shiftL/shiftT (blocks the original content was shifted
-- by, expandShiftL/T) are recorded when supplied so undo/redo can restore
-- the editor's block-revert mapping along with the data.  mapId tags the
-- snapshot with the map it belongs to: nil for the edited map, the map id
-- for a connected map painted across a seam, so undo/redo re-apply each
-- step to the right def.
function Undo:capture(def, shiftL, shiftT, mapId)
  table.insert(self._undoStack, {
    blocks      = deepCopy(def.blocks),
    warps       = deepCopy(def.warps),
    objects     = deepCopy(def.objects),
    signs       = deepCopy(def.signs),
    connections = deepCopy(def.connections),
    width       = def.width,
    height      = def.height,
    borderBlock = def.borderBlock,
    shiftL      = shiftL,
    shiftT      = shiftT,
    mapId       = mapId,
  })
  if #self._undoStack > MAX_UNDO then
    table.remove(self._undoStack, 1)
  end
  -- Discard any redo history since a new change invalidates it.
  self._redoStack = {}
end

local function snapshotOf(def, shiftL, shiftT, mapId)
  return {
    blocks      = deepCopy(def.blocks),
    warps       = deepCopy(def.warps),
    objects     = deepCopy(def.objects),
    signs       = deepCopy(def.signs),
    connections = deepCopy(def.connections),
    width       = def.width,
    height      = def.height,
    borderBlock = def.borderBlock,
    shiftL      = shiftL,
    shiftT      = shiftT,
    mapId       = mapId,
  }
end

-- Applies a snapshot's fields back onto the map definition.
local function apply(def, snapshot)
  for i, v in ipairs(snapshot.blocks) do def.blocks[i] = v end
  -- Truncate any extra blocks left over from a previous expansion.
  for i = #snapshot.blocks + 1, #def.blocks do def.blocks[i] = nil end
  def.warps       = deepCopy(snapshot.warps)
  def.objects     = deepCopy(snapshot.objects)
  def.signs       = deepCopy(snapshot.signs)
  def.connections = deepCopy(snapshot.connections)
  def.width       = snapshot.width
  def.height      = snapshot.height
  def.borderBlock = snapshot.borderBlock
end

-- Restores the previous snapshot and returns it, or returns nil if there
-- is nothing to undo.  shiftL/shiftT carry the current shift into the redo
-- snapshot; the popped snapshot's own shift fields restore expandShiftL/T.
-- mapId tags the pushed redo snapshot with the def it belongs to (nil for
-- the edited map) so a later redo re-applies to the same map.
function Undo:undo(def, shiftL, shiftT, mapId)
  if #self._undoStack == 0 then return nil end
  table.insert(self._redoStack, snapshotOf(def, shiftL, shiftT, mapId))
  local snap = table.remove(self._undoStack)
  apply(def, snap)
  return snap
end

-- Restores the next snapshot after an undo and returns it, or returns nil
-- if there is nothing to redo.
function Undo:redo(def, shiftL, shiftT, mapId)
  if #self._redoStack == 0 then return nil end
  table.insert(self._undoStack, snapshotOf(def, shiftL, shiftT, mapId))
  local snap = table.remove(self._redoStack)
  apply(def, snap)
  return snap
end

-- The undo or redo stack, for peek-ahead (which map does the next step
-- belong to?).
function Undo:stack(kind)
  if kind == "redo" then return self._redoStack end
  return self._undoStack
end

-- Returns true if at least one undo step is available.
function Undo:canUndo()
  return #self._undoStack > 0
end

-- Returns true if at least one redo step is available.
function Undo:canRedo()
  return #self._redoStack > 0
end

return Undo