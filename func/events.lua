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

function Events.onKeyPressed(self, key)
  if self.game.stack:top() ~= self then
    if key == "1" or key == "2" or key == "3" or key == "4" or key == "5" or key == "6" then
      while self.game.stack:top() ~= self do self.game.stack:pop() end
    else
      return
    end
  end

  if self.entityMoving then
    local ent = self.entityMovingTarget
    if key == "up" or key == "w" then ent.y = math.max(0, ent.y - 1)
    elseif key == "down" or key == "s" then ent.y = ent.y + 1
    elseif key == "left" or key == "a" then ent.x = math.max(0, ent.x - 1)
    elseif key == "right" or key == "d" then ent.x = ent.x + 1
    elseif key == "return" or key == "space" then
      self.entityMoving = false
      self.entityMovingKind = nil
      self.entityMovingTarget = nil
      self.entityMovingOrig = nil
      self.mapChanged = true
    elseif key == "escape" then
      ent.x = self.entityMovingOrig.x
      ent.y = self.entityMovingOrig.y
      self.entityMoving = false
      self.entityMovingKind = nil
      self.entityMovingTarget = nil
      self.entityMovingOrig = nil
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
    local step = (self.mode == MODES.BLOCKS) and 2 or 1
    if key == "up" or key == "w" then self.cursorBy = self.cursorBy - step
    elseif key == "down" or key == "s" then self.cursorBy = self.cursorBy + step
    elseif key == "left" or key == "a" then self.cursorBx = self.cursorBx - step
    elseif key == "right" or key == "d" then self.cursorBx = self.cursorBx + step end
  elseif key == "tab" then self.showPalette = not self.showPalette
  elseif key == "q" then
    if self.mode == MODES.OBJECTS and #self.spriteList > 0 then
      local kind, ent = EntityEditor.selectedEntity(self)
      if kind == "object" and ent then
        if self.undo then self.undo:capture(self.def) end
        for i = #self.spriteList, 1, -1 do
          if self.spriteList[i] == ent.sprite then
            local prev = (i - 2 + #self.spriteList) % #self.spriteList + 1
            ent.sprite = self.spriteList[prev]
            self.selectedBlock = prev
            self.mapChanged = true
            break
          end
        end
      else
        self.selectedBlock = (self.selectedBlock - 2 + #self.spriteList) % #self.spriteList + 1
      end
    else
      self.selectedBlock = (self.selectedBlock - 1 + #self.tileset.blocks) % #self.tileset.blocks
    end
  elseif key == "e" then
    if self.mode == MODES.OBJECTS and #self.spriteList > 0 then
      local kind, ent = EntityEditor.selectedEntity(self)
      if kind == "object" and ent then
        if self.undo then self.undo:capture(self.def) end
        for i = 1, #self.spriteList do
          if self.spriteList[i] == ent.sprite then
            local next = i % #self.spriteList + 1
            ent.sprite = self.spriteList[next]
            self.selectedBlock = next
            self.mapChanged = true
            break
          end
        end
      else
        self.selectedBlock = self.selectedBlock % #self.spriteList + 1
      end
    else
      self.selectedBlock = (self.selectedBlock + 1) % #self.tileset.blocks
    end
  -- elseif key == "f" and self.mode == MODES.BLOCKS then self:floodFill()
  elseif key == "f" and self.mode == MODES.BLOCKS then self:selectCursorBlock()
  elseif key == "g" then self.showGrid = not self.showGrid
  elseif key == "h" then self.showHelp = not self.showHelp
  elseif key == "1" then self.mode = MODES.BLOCKS
  elseif key == "2" then self.mode = MODES.WARPS
  elseif key == "3" then self.mode = MODES.OBJECTS
  elseif key == "4" then self.mode = MODES.SIGNS
  elseif key == "5" then
    self.mode = MODES.ENCOUNTERS
    require("mods.map_editor.scene.encounter_editor").edit(self)
  elseif key == "6" then
    local ent = EntityEditor.selectedEntity(self)
    if ent and ent.kind == "connection" then
      require("mods.map_editor.scene.connection_editor").edit(self, ent)
    else
      self.mode = MODES.CONNECTIONS
    end
  elseif key == "return" or key == "space" then
    if self.mode == MODES.BLOCKS then self:paintBlock()
    elseif self.mode == MODES.ENCOUNTERS then
      require("mods.map_editor.scene.encounter_editor").edit(self)
    else
      local kind, ent = EntityEditor.selectedEntity(self)
      if kind then EntityEditor.editEntity(self, kind, ent)
      elseif self.mode == MODES.WARPS then EntityEditor.addEntity(self, "warp")
      elseif self.mode == MODES.OBJECTS then EntityEditor.showObjectTypePicker(self)
      elseif self.mode == MODES.SIGNS then EntityEditor.addEntity(self, "sign") end
    end
  elseif key == "r" and self.mode == MODES.BLOCKS then self:revertBlock()
  elseif key == "n" then self:newMapDialog()
  elseif key == "escape" then
    if self._newMapState then self._newMapState = nil
    elseif self.showHelp then self.showHelp = false
    else self.game.stack:pop() end
  end
  self:clampScroll()
end

return Events
