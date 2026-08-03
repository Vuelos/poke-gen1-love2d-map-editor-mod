-- Input handler for entity/connection moving mode.

local InputHelpers = require("mods.map_editor.inputs.input_helpers")
local EntityEditor = require("mods.map_editor.scene.entity_editor")
local Common = require("mods.map_editor.func.common")
local MODES = Common.MODES

local InputMove = {}

function InputMove.onKeyPressed(self, key)
  if not self.entityMoving then return false end

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
      self.entityMoving = false; self.entityMovingKind = nil
      self.entityMovingTarget = nil; self.entityMovingOrig = nil
      self.mapChanged = true
      EntityEditor.editEntity(self, "connection", conn)
      return true
    elseif key == "escape" then
      InputHelpers.cancelMove(self)
      return true
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
      self.entityMoving = false; self.entityMovingKind = nil
      self.entityMovingTarget = nil; self.entityMovingOrig = nil
      self.mapChanged = true
      return true
    elseif key == "escape" then
      InputHelpers.cancelMove(self)
      return true
    end
  end
  return true
end

return InputMove