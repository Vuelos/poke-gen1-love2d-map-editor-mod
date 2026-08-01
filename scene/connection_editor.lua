-- Connection editor for the map editor: edits connection warps (Width/Height/Direction/OffsetX/OffsetY).
-- Allows editing existing connections or creating new ones.
-- Uses LÖVE callbacks (onKeyPressed, draw, enter, exit) and is pushed onto the game stack.

local MapEditor = require("mods.map_editor.scene.map_editor")
local ConnectionEditorDialog = require("mods.map_editor.renderer.connection_editor")

local CONNECTIONS = { "N", "E", "S", "W" }

local ConnectionEditor = {}

local function applyField(state, field, delta)
  if field == "width" then state.width = math.max(1, state.width + delta)
  elseif field == "height" then state.height = math.max(1, state.height + delta)
  elseif field == "offsetX" then state.offsetX = math.max(-64, math.min(64, state.offsetX + delta))
  elseif field == "offsetY" then state.offsetY = math.max(-64, math.min(64, state.offsetY + delta))
  end
end

local function cycleDirection(state, dir)
  local i = 1
  while i <= 4 and CONNECTIONS[i] ~= state.dir do i = i + 1 end
  if dir == "left" then state.dir = CONNECTIONS[i % 4 + 1]
  else state.dir = CONNECTIONS[((i - 2) % 4) + 1] end
end

local function confirmConnection(screen, state, existing)
  if existing then
    for k, v in pairs(state) do existing[k] = v end
    screen.mapChanged = true
  else
    local conn = { width = state.width, height = state.height, dir = state.dir, offsetX = state.offsetX, offsetY = state.offsetY }
    table.insert(screen.def.connections, conn)
    screen.mapChanged = true
  end
end

function ConnectionEditor.edit(screen, existing)
  local state = {
    editField = "width",
    width = existing and existing.width or 2,
    height = existing and existing.height or 2,
    dir = existing and existing.dir or "N",
    offsetX = existing and existing.offsetX or 0,
    offsetY = existing and existing.offsetY or 0,
  }

  local connState = {
    screen = screen,
    state = state,
    existing = existing,
  }

  function connState:onKeyPressed(key)
    local s = self.state
    local scr = self.screen

    if key == "left" or key == "a" then
      if s.editField == "width" or s.editField == "height" or s.editField == "offsetX" or s.editField == "offsetY" then
        applyField(s, s.editField, -1)
      else
        cycleDirection(s, "left")
      end
    elseif key == "right" or key == "d" then
      if s.editField == "width" or s.editField == "height" or s.editField == "offsetX" or s.editField == "offsetY" then
        applyField(s, s.editField, 1)
      else
        cycleDirection(s, "right")
      end
    elseif key == "up" or key == "w" then
      local fields = { "width", "height", "dir", "offsetX", "offsetY" }
      for i = 1, #fields do
        if fields[i] == s.editField then
          local nextI = ((i - 1) + (key == "up" and -1 or 1)) % #fields + 1
          s.editField = fields[nextI]
          break
        end
      end
    elseif key == "down" or key == "s" then
      local fields = { "width", "height", "dir", "offsetX", "offsetY" }
      for i = 1, #fields do
        if fields[i] == s.editField then
          local nextI = ((i - 1) + (key == "down" and 1 or -1)) % #fields + 1
          s.editField = fields[nextI]
          break
        end
      end
    elseif key == "return" or key == "space" then
      confirmConnection(scr, s, self.existing)
      scr.game.stack:pop()
    elseif key == "escape" then
      scr.game.stack:pop()
    end
  end

  function connState:draw()
    love.graphics.setScissor(0, 8, 160, 144)
    ConnectionEditorDialog.draw(self)
    love.graphics.setScissor()
  end

  function connState:enter()
    self.screen.mode = MapEditor.MODES.BLOCKS
    self.screen:clampScroll()
  end

  function connState:exit()
  end

  screen.game.stack:push(connState)
end

return ConnectionEditor