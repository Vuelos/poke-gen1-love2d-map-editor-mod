local NewMapDialog = {}

function NewMapDialog.draw(screen)
  local s = screen._newMapState
  if not s then return end
  local vw, vh = require("src.render.Renderer"):uiSize()
  local boxX, boxY = 4, vh - 18
  local boxW, boxH = vw - 8, 10
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", boxX, boxY, boxW, boxH)
  local function drawField(label, value, active, offset)
    local full = label .. value
    if active then love.graphics.setColor(1, 0, 0, 1)
    else love.graphics.setColor(0, 0, 0, 1) end
    screen.font.draw(full, boxX + 4 + offset, boxY + 1)
    return offset + screen.font.width(full) + 8
  end
  local off = 0
  off = drawField("W:", tostring(s.width), s.editField == "w", off)
  off = drawField("H:", tostring(s.height), s.editField == "h", off)
  drawField("Dir:", s.dir, s.editField == "dir", off)
  love.graphics.setColor(1, 1, 1, 1)
end

return NewMapDialog