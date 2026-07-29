-- Camera / scroll management for the map editor: viewport clamping,
-- zoom stub, and block-pixel conversion.

local Common = require("mods.map_editor.func.common")
local CELL_PX = Common.CELL_PX
local BLOCK_PX = Common.BLOCK_PX

local Camera = {}

function Camera.clampScroll(self)
  local vw = 160; local palW = self.showPalette and 40 or 0; local mapViewW = vw - palW
  local viewW = mapViewW; local viewH = 136
  local cellSpan = (self.mode == Common.MODES.BLOCKS) and 2 or self.brushSize
  local size = cellSpan * CELL_PX
  local tx = self.cursorBx * CELL_PX; local ty = self.cursorBy * CELL_PX
  if tx < self.scrollX then self.scrollX = tx end
  if tx + size > self.scrollX + viewW then self.scrollX = tx + size - viewW end
  if ty < self.scrollY then self.scrollY = ty end
  if ty + size > self.scrollY + viewH then self.scrollY = ty + size - viewH end
  local minScrollX = -CELL_PX * 16
  local minScrollY = -CELL_PX * 16
  local maxScrollX = math.max(minScrollX, self.mapW - viewW + CELL_PX * 16)
  local maxScrollY = math.max(minScrollY, self.mapH - viewH + CELL_PX * 16)
  self.scrollX = math.max(minScrollX, math.min(self.scrollX, maxScrollX))
  self.scrollY = math.max(minScrollY, math.min(self.scrollY, maxScrollY))
end

function Camera.zoomScale()
  return 1
end

function Camera.blockPx()
  return BLOCK_PX
end

return Camera
