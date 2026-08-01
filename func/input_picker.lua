-- Input handler for the sprite picker mode.  Movement is shared with the
-- palette focus cursor: WASD/arrows go through Palette.move, which scrolls
-- the palette page as it travels so every sprite in the list stays
-- reachable.  Enter confirms the sprite under the cursor, Escape cancels.

local Palette = require("mods.map_editor.scene.palette")
local EntityEditor = require("mods.map_editor.scene.entity_editor")

local InputPicker = {}

function InputPicker.onKeyPressed(self, key)
  if not self._spritePicker then return false end

  if key == "up" or key == "w" or key == "down" or key == "s"
     or key == "left" or key == "a" or key == "right" or key == "d" then
    Palette.move(self, key)
    return true
  end

  if key == "return" or key == "space" then
    local picker = self._spritePicker
    Palette.ensureCursor(self)
    local cols = Palette.cols(self)
    local index = (self.paletteCursorY - 1) * cols + self.paletteCursorX
    local list = Palette.list(self)
    local targetId = list and list[index]
    self.selectedBlock = targetId ~= nil and index or self.selectedBlock
    local ent, kind = picker.ent, picker.kind
    if kind == "object" and ent and targetId and ent.sprite ~= targetId then
      if self.undo then self.undo:capture(self.def) end
      ent.sprite = targetId
      self.mapChanged = true
      EntityEditor.refreshMenuItems(self, kind, ent)
    end
    self._spritePicker = nil
    Palette.unfocus(self)
    return true
  end

  if key == "escape" then
    self._spritePicker = nil
    Palette.unfocus(self)
    return true
  end

  -- Swallow every other key while the picker is open so the editor's
  -- mode/help/movement keys can't fire underneath it.
  return true
end

return InputPicker
