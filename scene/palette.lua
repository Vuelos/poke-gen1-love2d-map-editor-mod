-- Palette scene module: focus, cursor, navigation and selection state for
-- the right-hand palette panel.  The panel is drawn inside the main editor
-- canvas (see renderer/palette.lua) but its input and state logic live here,
-- keeping the map editor scene focused on the map itself.

local Common = require("mods.map_editor.func.common")
local MODES = Common.MODES

local Palette = {}

-- Column counts: blocks use 3 columns, sprites use 4.
local BLOCK_COLS = 3
local SPRITE_COLS = 4

-- The active list depends on mode: sprite ids in ENT mode, block ids
-- otherwise.
function Palette.list(screen)
  if screen.mode == MODES.ENT then return screen.spriteList or {} end
  return screen.paletteList or {}
end

function Palette.cols(screen)
  return screen.mode == MODES.ENT and SPRITE_COLS or BLOCK_COLS
end

-- Rows of palette cells that fit in the current UI height.
function Palette.visibleRows(screen)
  local _, vh = require("src.render.Renderer"):uiSize()
  if screen.mode == MODES.ENT then
    return math.max(2, math.floor((vh - 18) / 24))
  end
  return math.max(2, math.floor((vh - 18) / 40))
end

function Palette.perPage(screen)
  return Palette.visibleRows(screen) * Palette.cols(screen)
end

-- Index (1-based) of the selected item within the active palette list.
function Palette.selectedIndex(screen)
  local list = Palette.list(screen)
  if #list == 0 then return 1 end
  if screen.mode == MODES.ENT then
    return math.max(1, math.min(#list, screen.selectedBlock or 1))
  end
  local sel = screen.selectedBlock or 0
  for i, id in ipairs(list) do
    if id == sel then return i end
  end
  return 1
end

function Palette.ensureCursor(screen)
  screen.paletteCursorX = screen.paletteCursorX or 1
  screen.paletteCursorY = screen.paletteCursorY or 1
end

-- Gives the palette input focus and parks the cursor on the selected item.
function Palette.focus(screen)
  if screen.mode == MODES.ENC then return end
  screen.paletteFocus = true
  Palette.ensureCursor(screen)
  local cols = Palette.cols(screen)
  local idx = Palette.selectedIndex(screen)
  screen.paletteCursorX = (idx - 1) % cols + 1
  screen.paletteCursorY = math.floor((idx - 1) / cols) + 1
  Palette.scrollToCursor(screen)
end

function Palette.unfocus(screen)
  screen.paletteFocus = false
end

function Palette.toggleFocus(screen)
  if screen.mode == MODES.ENC then return end
  if screen.paletteFocus then
    Palette.unfocus(screen)
  else
    Palette.focus(screen)
  end
end

-- Scrolls the palette page so the cursor stays within the visible cells.
function Palette.scrollToCursor(screen)
  Palette.ensureCursor(screen)
  local cols = Palette.cols(screen)
  local perPage = Palette.perPage(screen)
  local idx = (screen.paletteCursorY - 1) * cols + screen.paletteCursorX
  local off = screen.paletteOffset or 0
  local maxOff = math.max(0, #Palette.list(screen) - perPage)
  if idx <= off then
    screen.paletteOffset = math.max(0, idx - 1)
  elseif idx > off + perPage then
    screen.paletteOffset = math.min(maxOff, math.max(0, idx - perPage))
  end
  screen.paletteOffset = math.max(0, math.min(screen.paletteOffset, maxOff))
end

-- Moves the palette cursor with WASD/arrows.  Returns true when the key was
-- a movement key (even if the cursor could not move further).
function Palette.move(screen, key)
  Palette.ensureCursor(screen)
  local list = Palette.list(screen)
  if #list == 0 then return true end
  local cols = Palette.cols(screen)
  local rows = math.ceil(#list / cols)
  if key == "up" or key == "w" then
    screen.paletteCursorY = math.max(1, screen.paletteCursorY - 1)
  elseif key == "down" or key == "s" then
    screen.paletteCursorY = math.min(rows, screen.paletteCursorY + 1)
  elseif key == "left" or key == "a" then
    if screen.paletteCursorX > 1 then
      screen.paletteCursorX = screen.paletteCursorX - 1
    elseif screen.paletteCursorY > 1 then
      screen.paletteCursorY = screen.paletteCursorY - 1
      screen.paletteCursorX = cols
    end
  elseif key == "right" or key == "d" then
    if screen.paletteCursorX < cols then
      screen.paletteCursorX = screen.paletteCursorX + 1
    elseif screen.paletteCursorY < rows then
      screen.paletteCursorY = screen.paletteCursorY + 1
      screen.paletteCursorX = 1
    end
  else
    return false
  end
  -- Clamp to the last real item so the cursor cannot rest on an empty cell.
  local idx = (screen.paletteCursorY - 1) * cols + screen.paletteCursorX
  if idx > #list then
    screen.paletteCursorY = math.ceil(#list / cols)
    screen.paletteCursorX = (#list - 1) % cols + 1
  end
  Palette.scrollToCursor(screen)
  return true
end

-- Selects the item under the palette cursor.
function Palette.select(screen)
  Palette.ensureCursor(screen)
  local list = Palette.list(screen)
  if #list == 0 then return end
  local cols = Palette.cols(screen)
  local idx = (screen.paletteCursorY - 1) * cols + screen.paletteCursorX
  local item = list[idx]
  if item == nil then return end
  if screen.mode == MODES.ENT then
    screen.selectedBlock = idx
  else
    screen.selectedBlock = item
  end
  Palette.scrollToCursor(screen)
end

return Palette
