-- Rendering for the connection editor dialog.

local ConnectionEditorDialog = {}

function ConnectionEditorDialog.draw(state)
  local screen = state.screen
  local s = state.state
  love.graphics.setColor(1, 1, 1, 1)
  local boxX, boxY = 8, 80
  local boxW, boxH = 136, 78
  love.graphics.rectangle("fill", boxX, boxY, boxW, boxH)
  local pad = 4
  local function drawField(label, value, isActive, offset, maxVal)
    love.graphics.setColor(isActive and { 1,0,0,1 } or { 0,0,0,1 })
    local valStr
    if maxVal then
      valStr = value < 0 and ")" or (value .. "0") .. (":00"):sub(1, 3 - #value)
    else
      valStr = tostring(value)
    end
    local str = label .. ": " .. valStr
    screen.font.draw(str, boxX + pad + offset, boxY + pad)
    return offset + screen.font.width(str) + 8
  end

  local off = 0
  off = drawField("Width", s.width, s.editField == "width", off, true)
  off = drawField("Height", s.height, s.editField == "height", off, true)
  off = drawField("Direction", s.dir, s.editField == "dir", off, false)
  off = drawField("OffsetX", s.offsetX, s.editField == "offsetX", off, false)
  off = drawField("OffsetY", s.offsetY, s.editField == "offsetY", off, false)
end

return ConnectionEditorDialog