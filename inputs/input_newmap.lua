-- Input handler for the new map dialog's dimensions step (the name is chosen
-- first, before this step, so no name key appears here).
-- Width/height are edited directly: A/Left shrink width, D/Right grow
-- width, W/Up grow height, S/Down shrink height; Q/E adjust the active
-- numeric field by +/-10.  Tab cycles the active field (W -> H -> Dir);
-- while "dir" is active the Left/Right arrows cycle the direction.

local InputNewMap = {}

function InputNewMap.onKeyPressed(self, key)
  if not self._newMapState or not self._newMapState.editField then return false end

  local s = self._newMapState
  local fields = s.lockDir and { "w", "h" } or { "w", "h", "dir" }

  if key == "a" or key == "left" then
    if s.editField == "dir" and key == "left" then
      local dirs = { "N", "W", "S", "E" }
      for i = 1, 4 do
        if dirs[i] == s.dir then s.dir = dirs[i % 4 + 1]; break end
      end
    else
      s.width = math.max(1, s.width - 1)
    end
  elseif key == "d" or key == "right" then
    if s.editField == "dir" and key == "right" then
      local dirs = { "N", "E", "S", "W" }
      for i = 1, 4 do
        if dirs[i] == s.dir then s.dir = dirs[i % 4 + 1]; break end
      end
    else
      s.width = math.min(64, s.width + 1)
    end
  elseif key == "w" or key == "up" then
    s.height = math.min(64, s.height + 1)
  elseif key == "s" or key == "down" then
    s.height = math.max(1, s.height - 1)
  elseif key == "q" then
    if s.editField == "w" then s.width = math.max(1, s.width - 10)
    elseif s.editField == "h" then s.height = math.max(1, s.height - 10) end
  elseif key == "e" then
    if s.editField == "w" then s.width = math.min(64, s.width + 10)
    elseif s.editField == "h" then s.height = math.min(64, s.height + 10) end
  elseif key == "tab" then
    for i = 1, #fields do
      if fields[i] == s.editField then
        s.editField = fields[i % #fields + 1]
        break
      end
    end
  elseif key == "return" or key == "space" then
    self:_newMapConfirm()
    return true
  elseif key == "escape" then
    self._newMapState = nil
    return true
  end

  return true
end

-- Polls the gamepad while the new-map dialog's dimensions step is active
-- (the editor is the top state then, so this runs from MapEditor:update):
-- the D-pad drives the same arrows as the keyboard, A confirms, B cancels.
-- Keyboard input never overlaps -- while the editor is on top, Game routes
-- raw keys to onKeyPressed and skips the Input abstraction.
function InputNewMap.updateGamepad(self)
  if not self._newMapState or not self._newMapState.editField then return end
  local input = self.game and self.game.input
  if not input or not input.wasPressed then return end
  if input:wasPressed("up") then InputNewMap.onKeyPressed(self, "up")
  elseif input:wasPressed("down") then InputNewMap.onKeyPressed(self, "down")
  elseif input:wasPressed("left") then InputNewMap.onKeyPressed(self, "left")
  elseif input:wasPressed("right") then InputNewMap.onKeyPressed(self, "right")
  elseif input:wasPressed("a") then InputNewMap.onKeyPressed(self, "return")
  elseif input:wasPressed("b") then InputNewMap.onKeyPressed(self, "escape")
  end
end

return InputNewMap