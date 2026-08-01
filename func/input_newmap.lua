-- Input handler for the new map creation dialog.

local InputNewMap = {}

function InputNewMap.onKeyPressed(self, key)
  if not self._newMapState or not self._newMapState.editField then return false end

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
    for i = 1, #fields do
      if fields[i] == s.editField then
        s.editField = fields[(key == "up" and (i - 2) or i) % 3 + 1]
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

return InputNewMap