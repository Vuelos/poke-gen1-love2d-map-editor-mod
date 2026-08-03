-- Camera / scroll management for the map editor: viewport clamping,
-- zoom stub, and block-pixel conversion.

local Common = require("mods.map_editor.func.common")
local CELL_PX = Common.CELL_PX
local BLOCK_PX = Common.BLOCK_PX

local Camera = {}

function Camera.clampScroll(self)
  local vw, vh = require("src.render.Renderer"):uiSize()
  local palW = self.showPalette and Common.PAL_W or 0
  local viewW = vw - palW
  local viewH = vh - 8
  local cellSpan = (self.mode == Common.MODES.MAP) and 2 or self.brushSize
  local size = cellSpan * CELL_PX
  local tx = self.cursorBx * CELL_PX; local ty = self.cursorBy * CELL_PX
  if tx < self.scrollX then self.scrollX = tx end
  if tx + size > self.scrollX + viewW then self.scrollX = tx + size - viewW end
  if ty < self.scrollY then self.scrollY = ty end
  if ty + size > self.scrollY + viewH then self.scrollY = ty + size - viewH end
  -- The scrollable world is the edited map plus everything connected to
  -- it, so seams (and their strips) stay reachable in MAP mode.
  local minX, minY = 0, 0
  local maxX, maxY = self.mapW, self.mapH
  for _, nb in ipairs(self.neighbors or {}) do
    minX = math.min(minX, nb.ox)
    minY = math.min(minY, nb.oy)
    maxX = math.max(maxX, nb.ox + nb.def.width * BLOCK_PX)
    maxY = math.max(maxY, nb.oy + nb.def.height * BLOCK_PX)
  end
  local minScrollX = minX - CELL_PX * 16
  local minScrollY = minY - CELL_PX * 16
  local maxScrollX = math.max(minScrollX, maxX - viewW + CELL_PX * 16)
  local maxScrollY = math.max(minScrollY, maxY - viewH + CELL_PX * 16)
  self.scrollX = math.max(minScrollX, math.min(self.scrollX, maxScrollX))
  self.scrollY = math.max(minScrollY, math.min(self.scrollY, maxScrollY))

  -- While dragging a connection silhouette the cursor sits on the far side
  -- of the 64px strip, so plain cursor-following shoves the whole edited map
  -- off the opposite edge.  Clamp per direction instead: when the map is
  -- smaller than the viewport the whole map (plus the strip) stays visible,
  -- and when it is larger the map body fills the viewport with the seam
  -- pinned to its edge.
  if self.entityMoving and self.entityMovingKind == "connection" and self._selectedDir then
    local strip = Common.BLOCK_PX * 2
    local dir = self._selectedDir
    if dir == "east" then
      self.scrollX = math.max(self.mapW - viewW, math.min(self.scrollX, self.mapW + strip - viewW))
    elseif dir == "west" then
      self.scrollX = math.max(-strip, math.min(self.scrollX, 0))
    elseif dir == "south" then
      self.scrollY = math.max(self.mapH - viewH, math.min(self.scrollY, self.mapH + strip - viewH))
    elseif dir == "north" then
      self.scrollY = math.max(-strip, math.min(self.scrollY, 0))
    end
  end
end

function Camera.zoomScale()
  return require("src.render.Zoom").offset
end

function Camera.blockPx()
  return BLOCK_PX
end

return Camera
