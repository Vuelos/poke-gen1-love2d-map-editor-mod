-- Event dispatcher for the map editor: routes keys to mode-specific
-- handlers (move, new-map dialog, sprite picker) and handles
-- global keys (save, undo, mode switch, cursor movement, paint, revert).

local Common = require("mods.map_editor.func.common")
local EntityEditor = require("mods.map_editor.scene.entity_editor")
local InputMove = require("mods.map_editor.inputs.input_move")
local InputNewMap = require("mods.map_editor.inputs.input_newmap")
local InputPicker = require("mods.map_editor.inputs.input_picker")
local InputHelpers = require("mods.map_editor.inputs.input_helpers")
local Palette = require("mods.map_editor.scene.palette")
local MODES = Common.MODES

local Events = {}

function Events.onKeyPressed(self, key)
  if self.game.stack:top() ~= self then
    if key == "1" or key == "2" or key == "3" then
      while self.game.stack:top() ~= self do self.game.stack:pop() end
    else
      return
    end
  end

  if InputMove.onKeyPressed(self, key) then return end
  if InputNewMap.onKeyPressed(self, key) then return end
  if InputPicker.onKeyPressed(self, key) then return end

  if key == "s" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then self:savePatches()
  elseif key == "e" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then self:exportAllEdits()
  elseif key == "i" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then self:importAllEdits()
  elseif key == "z" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then self:restoreSnapshot("undo")
  elseif key == "y" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then self:restoreSnapshot("redo")
  elseif key == "tab" and not (self._newMapState and self._newMapState.editField) then
    Palette.toggleFocus(self)
  elseif self.paletteFocus and not (self._newMapState and self._newMapState.editField) then
    -- Palette has focus: WASD/arrows move the palette cursor, Enter/Space
    -- select the item under it, and Q/E jump the cursor 10 items at a time
    -- (blocks and sprites alike).
    if Palette.move(self, key) then
      -- cursor moved
    elseif key == "return" or key == "space" then
      Palette.select(self)
    elseif key == "q" then
      Palette.jump(self, -10)
    elseif key == "e" then
      Palette.jump(self, 10)
    elseif key == "g" then self.showGrid = not self.showGrid
    elseif key == "h" then self.showHelp = not self.showHelp
    elseif key == "1" then
      self.paletteFocus = false
      InputHelpers.cancelMove(self)
      self.mode = MODES.MAP
      self:snapCursorToBlock()
    elseif key == "2" then
      self.paletteFocus = false
      InputHelpers.cancelMove(self)
      if self.mode == MODES.MAP then
        local nb = self:mapUnderCursor()
        if nb then self:switchToMap(nb) end
      end
      self.mode = MODES.ENT
    elseif key == "3" then
      self.paletteFocus = false
      InputHelpers.cancelMove(self)
      if self.mode == MODES.MAP then
        local nb = self:mapUnderCursor()
        if nb then self:switchToMap(nb) end
      end
      self.mode = MODES.ENC
      require("mods.map_editor.scene.encounter_editor").edit(self)
    elseif key == "escape" then
      Palette.unfocus(self)
    end
  elseif key == "up" or key == "w" or key == "down" or key == "s" or key == "left" or key == "a" or key == "right" or key == "d" then
    local step = (self.mode == MODES.MAP) and 2 or 1
    if key == "up" or key == "w" then self.cursorBy = self.cursorBy - step
    elseif key == "down" or key == "s" then self.cursorBy = self.cursorBy + step
    elseif key == "left" or key == "a" then self.cursorBx = self.cursorBx - step
    elseif key == "right" or key == "d" then self.cursorBx = self.cursorBx + step end
  elseif key == "q" and self.mode == MODES.ENT then
    EntityEditor.cycleEntity(self, "prev")
  elseif key == "e" and self.mode == MODES.ENT then
    EntityEditor.cycleEntity(self, "next")
  elseif key == "f" and self.mode == MODES.MAP then self:selectCursorBlock()
  elseif key == "g" then self.showGrid = not self.showGrid
  elseif key == "h" then self.showHelp = not self.showHelp
  elseif key == "1" then
    InputHelpers.cancelMove(self)
    self.mode = MODES.MAP
    self:snapCursorToBlock()
  elseif key == "2" then
    InputHelpers.cancelMove(self)
    if self.mode == MODES.MAP then
      local nb = self:mapUnderCursor()
      if nb then self:switchToMap(nb) end
    end
    self.mode = MODES.ENT
  elseif key == "3" then
    InputHelpers.cancelMove(self)
    if self.mode == MODES.MAP then
      local nb = self:mapUnderCursor()
      if nb then self:switchToMap(nb) end
    end
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