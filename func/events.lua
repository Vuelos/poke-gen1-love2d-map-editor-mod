-- Event handlers for the map editor: mouse, keyboard, and the hooks that
-- install/uninstall them at the love.* level.

local Common = require("mods.map_editor.func.common")
local EntityEditor = require("mods.map_editor.scene.entity_editor")
local MODES = Common.MODES
local CELL_PX = Common.CELL_PX
local PAL_BLOCK_SIZE = Common.PAL_BLOCK_SIZE
local PAL_GAP = Common.PAL_GAP
local PAL_ROWS = Common.PAL_ROWS
local PAL_COLS = Common.PAL_COLS
local PAL_VISIBLE = Common.PAL_VISIBLE

local Events = {}

-- Cancels an in-progress entity move, restoring the pre-move position.
local function cancelMove(self)
  if not self.entityMoving then return end
  local ent = self.entityMovingTarget
  if self.entityMovingKind == "connection" then
    ent.offset = self.entityMovingOrig.offset
  else
    ent.x = self.entityMovingOrig.x
    ent.y = self.entityMovingOrig.y
  end
  self.entityMoving = false
  self.entityMovingKind = nil
  self.entityMovingTarget = nil
  self.entityMovingOrig = nil
end

function Events.onKeyPressed(self, key)
  if self.game.stack:top() ~= self then
    if key == "1" or key == "2" or key == "3" then
      while self.game.stack:top() ~= self do self.game.stack:pop() end
    else
      return
    end
  end

  if self.entityMoving then
    local ent = self.entityMovingTarget
    local kind = self.entityMovingKind
    if kind == "connection" then
      local dir = self._selectedDir
      if key == "left" or key == "a" then
        ent.offset = (ent.offset or 0) - 1
      elseif key == "right" or key == "d" then
        ent.offset = (ent.offset or 0) + 1
      elseif key == "up" or key == "w" then
        ent.offset = (ent.offset or 0) - 1
      elseif key == "down" or key == "s" then
        ent.offset = (ent.offset or 0) + 1
      elseif key == "return" or key == "space" then
        local conn = ent
        self.entityMoving = false; self.entityMovingKind = nil; self.entityMovingTarget = nil; self.entityMovingOrig = nil
        self.mapChanged = true
        EntityEditor.editEntity(self, "connection", conn)
        return
      elseif key == "escape" then
        cancelMove(self)
        return
      end
      -- Keep cursor positioned at connection zone so scroll follows the silhouette
      local mw = self.def.width * 2; local mh = self.def.height * 2
      local off = (ent.offset or 0) * 2
      if dir == "north" then self.cursorBx = off + mw / 2; self.cursorBy = -2
      elseif dir == "south" then self.cursorBx = off + mw / 2; self.cursorBy = mh + 2
      elseif dir == "west" then self.cursorBx = -2; self.cursorBy = off + mh / 2
      elseif dir == "east" then self.cursorBx = mw + 2; self.cursorBy = off + mh / 2 end
    else
      if key == "up" or key == "w" then ent.y = math.max(0, ent.y - 1)
      elseif key == "down" or key == "s" then ent.y = ent.y + 1
      elseif key == "left" or key == "a" then ent.x = math.max(0, ent.x - 1)
      elseif key == "right" or key == "d" then ent.x = ent.x + 1
      elseif key == "return" or key == "space" then
        self.entityMoving = false; self.entityMovingKind = nil; self.entityMovingTarget = nil; self.entityMovingOrig = nil
        self.mapChanged = true
      elseif key == "escape" then
        cancelMove(self)
      end
    end
    return
  end

  if self._newMapState and self._newMapState.editField then
    local s = self._newMapState
    if key == "left" then
      if s.editField == "w" then s.width = math.max(1, s.width - 1)
      elseif s.editField == "h" then s.height = math.max(1, s.height - 1)
      else
        local dirs = { "N", "W", "S", "E" }
        for i = 1, 4 do
          if dirs[i] == s.dir then s.dir = dirs[i % 4 + 1]; break end
        end
      end
    elseif key == "right" then
      if s.editField == "w" then s.width = math.min(64, s.width + 1)
      elseif s.editField == "h" then s.height = math.min(64, s.height + 1)
      else
        local dirs = { "N", "E", "S", "W" }
        for i = 1, 4 do
          if dirs[i] == s.dir then s.dir = dirs[i % 4 + 1]; break end
        end
      end
    elseif key == "up" or key == "down" then
      local fields = { "w", "h", "dir" }
      for i = 1, 3 do
        if fields[i] == s.editField then
          s.editField = fields[(key == "up" and (i - 2) or i) % 3 + 1]
          break
        end
      end
    elseif key == "return" or key == "space" then self:_newMapConfirm()
    elseif key == "escape" then self._newMapState = nil end
    return
  end

  if key == "s" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then self:savePatches()
  elseif key == "e" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then self:exportPatches()
  elseif key == "z" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then self:restoreSnapshot("undo")
  elseif key == "y" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then self:restoreSnapshot("redo")
  elseif key == "up" or key == "w" or key == "down" or key == "s" or key == "left" or key == "a" or key == "right" or key == "d" then
    local step = (self.mode == MODES.MAP) and 2 or 1
    if key == "up" or key == "w" then self.cursorBy = self.cursorBy - step
    elseif key == "down" or key == "s" then self.cursorBy = self.cursorBy + step
    elseif key == "left" or key == "a" then self.cursorBx = self.cursorBx - step
    elseif key == "right" or key == "d" then self.cursorBx = self.cursorBx + step end
  elseif key == "tab" then self.showPalette = not self.showPalette
  elseif key == "q" then
    if self.mode == MODES.ENT then
      EntityEditor.cycleEntity(self, "prev")
    else
      self.selectedBlock = (self.selectedBlock - 1 + #self.tileset.blocks) % #self.tileset.blocks
    end
  elseif key == "e" then
    if self.mode == MODES.ENT then
      EntityEditor.cycleEntity(self, "next")
    else
      self.selectedBlock = (self.selectedBlock + 1) % #self.tileset.blocks
    end
  -- elseif key == "f" and self.mode == MODES.MAP then self:floodFill()
  elseif key == "f" and self.mode == MODES.MAP then self:selectCursorBlock()
  elseif key == "g" then self.showGrid = not self.showGrid
  elseif key == "h" then self.showHelp = not self.showHelp
  elseif key == "1" then
    cancelMove(self)
    self.mode = MODES.MAP
    self:snapCursorToBlock()
  elseif key == "2" then
    cancelMove(self)
    self.mode = MODES.ENT
  elseif key == "3" then
    cancelMove(self)
    self.mode = MODES.ENC
    require("mods.map_editor.scene.encounter_editor").edit(self)
  elseif key == "return" or key == "space" then
    if self.mode == MODES.MAP then self:paintBlock()
    elseif self.mode == MODES.ENC then
      require("mods.map_editor.scene.encounter_editor").edit(self)
    else
      local kind, ent = EntityEditor.selectedEntity(self)
      if kind then EntityEditor.editEntity(self, kind, ent)
      else EntityEditor.showCreatePicker(self) end
    end
  elseif key == "r" and self.mode == MODES.MAP then self:revertBlock()
  elseif key == "escape" then
    if self._newMapState then self._newMapState = nil
    elseif self.showHelp then self.showHelp = false
    else self.game.stack:pop() end
  end
  self:clampScroll()
end

return Events
