-- Shared input helpers for the map editor event handlers.

local Common = require("mods.map_editor.func.common")
local EntityEditor = require("mods.map_editor.scene.entity_editor")
local MODES = Common.MODES

local InputHelpers = {}

-- Cancels an in-progress entity move, restoring the pre-move position.
function InputHelpers.cancelMove(self)
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

return InputHelpers