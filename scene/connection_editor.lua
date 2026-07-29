-- Connection editor for the map editor: edits connection warps (Width/Height/Direction/OffsetX/OffsetY).
-- Allows editing existing connections or creating new ones.

local EditorScreen = require("mods.map_editor.scene.editor_screen")
local text_input = require("mods.map_editor.func.text_input")

local CONNECTIONS = { "N", "E", "S", "W" }

local ConnectionEditor = {}

function ConnectionEditor.edit(screen, existing)
  local ent = existing or {}
  local state = { editField = "width", width = ent.width or 2, height = ent.height or 2, dir = ent.dir or "N", offsetX = ent.offsetX or 0, offsetY = ent.offsetY or 0 }

  local function drawDialog()
    love.graphics.setColor(1, 1, 1, 1)
    local boxX, boxY = 8, 80
    local boxW, boxH = 136, 78
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH)
    local pad = 4
    local function drawField(label, value, isActive, offset, maxVal)
      love.graphics.setColor(isActive and { 1,0,0,1 } or { 0,0,0,1 })
      local str = label .. ": " .. (maxVal and (value < 0 and ")" or (value .. "0") .. (":00":sub(1, 3 - #value)) or tostring(value))
      screen.font.draw(str, boxX + pad + offset, boxY + pad)
      return offset + screen.font.width(str) + 8
    end

    local off = 0
    off = drawField("Width", state.width, state.editField == "width", off, true)
    off = drawField("Height", state.height, state.editField == "height", off, true)
    off = drawField("Direction", state.dir, state.editField == "dir", off, false)
    off = drawField("OffsetX", state.offsetX, state.editField == "offsetX", off, false)
    off = drawField("OffsetY", state.offsetY, state.editField == "offsetY", off, false)
  end

  love.graphics.setScissor(0, 8, 160, 144)
  drawDialog()
  love.graphics.setScissor()

  screen.mode = EditorScreen.MODES.BLOCKS
  screen:clampScroll()

  while true do
    love.graphics.origin()
    love.graphics.clear()

    drawDialog()

    love.graphics.present()

    local ev = love.timer.step()
    for _, t in ipairs(screen.game.stack:toList()) do
      if t.update then t:update(ev) end
    end

    for _, t in ipairs(screen.game.stack:toList()) do
      if t.draw then t:draw() end
    end

    local key = love.event.wait()
    if not key then break end

    local action = key[1]
    local a1, a2 = key[2], key[3]

    if action == "textinput" then
      text_input.handleTextInput(screen, state.editField == "width" and "width" or state.editField == "height" and "height" or state.editField == "offsetX" and "offsetX" or state.editField == "offsetY" and "offsetY" or nil, state)
    elseif action == "keypressed" then
      if a1 == "left" then
        if state.editField == "width" then state.width = math.max(1, state.width - 1)
        elseif state.editField == "height" then state.height = math.max(1, state.height - 1)
        elseif state.editField == "offsetX" then state.offsetX = math.max(-64, state.offsetX - 1)
        elseif state.editField == "offsetY" then state.offsetY = math.max(-64, state.offsetY - 1)
        else
          local i = 1
          while i <= 4 and CONNECTIONS[i] ~= state.dir do i = i + 1 end
          state.dir = CONNECTIONS[i % 4 + 1]
        end
      elseif a1 == "right" then
        if state.editField == "width" then state.width = math.min(64, state.width + 1)
        elseif state.editField == "height" then state.height = math.min(64, state.height + 1)
        elseif state.editField == "offsetX" then state.offsetX = math.min(64, state.offsetX + 1)
        elseif state.editField == "offsetY" then state.offsetY = math.min(64, state.offsetY + 1)
        else
          local i = 1
          while i <= 4 and CONNECTIONS[i] ~= state.dir do i = i + 1 end
          state.dir = CONNECTIONS[i % 4 + 1]
        end
      elseif a1 == "up" or a1 == "down" then
        local fields = { "width", "height", "dir", "offsetX", "offsetY" }
        for i = 1, #fields do
          if fields[i] == state.editField then
            local nextI = ((i - 1) + (a1 == "up" and -1 or 1)) % #fields + 1
            state.editField = fields[nextI]
            break
          end
        end
  elseif a1 == "return" or a1 == "space" then
    if existing then
      for k, v in pairs(state) do existing[k] = v end
      screen.mapChanged = true
    else
      local conn = { width = state.width, height = state.height, dir = state.dir, offsetX = state.offsetX, offsetY = state.offsetY }
      table.insert(screen.def.connections, conn)
      screen.mapChanged = true
    end
    break
      elseif a1 == "escape" then
        break
      end
    end
  end
end

return ConnectionEditor
