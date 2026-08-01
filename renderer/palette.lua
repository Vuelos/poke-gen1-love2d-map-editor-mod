-- Palette renderer: draws the right-hand palette panel for the map editor.
-- Blocks are shown in a 3-column grid in MAP/ENC mode, sprites in a 2-column
-- grid in ENT mode.  The panel also renders the focus cursor (yellow) used
-- when the palette has input focus.

local Common = require("mods.map_editor.func.common")
local MODES = Common.MODES

local TILE_PX = 8
local BLOCK_SIZE = 32
local BLOCK_GAP = 4
local BLOCK_COLS = 3
local SPRITE_COLS = 2
local SPRITE_CELL = 32
local SPRITE_ROW = 24

local PaletteRenderer = {}

local function viewSize()
  return require("src.render.Renderer"):uiSize()
end

-- Draws the panel backdrop and border.
local function drawBackdrop(panelX, vw, vh)
  love.graphics.setColor(0.1, 0.1, 0.1, 0.85)
  love.graphics.rectangle("fill", panelX, 0, vw - panelX, vh)
  love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
  love.graphics.rectangle("line", panelX, 0, vw - panelX, vh)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Cursor box for the palette focus.  localIdx is the 1-based index of the
-- cursor within the visible page; cols/rowPitch describe the grid layout.
local function drawFocusCursor(screen, panelX, localIdx, cols, rowPitch, cellW, cellH)
  if not screen.paletteFocus then return end
  if not localIdx or localIdx < 1 then return end
  local row = math.floor((localIdx - 1) / cols)
  local col = (localIdx - 1) % cols
  local px = panelX + 4 + col * cellW
  local py = 10 + row * rowPitch
  love.graphics.setColor(1, 1, 0, 0.4)
  love.graphics.rectangle("fill", px - 2, py - 2, cellW + 4, cellH + 4)
  love.graphics.setColor(1, 1, 0, 0.9)
  love.graphics.rectangle("line", px - 2, py - 2, cellW + 4, cellH + 4)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Position of the focus cursor within the visible page (1-based), or nil
-- when it is scrolled out of view.
local function cursorLocalIndex(screen, cols, perPage)
  if not screen.paletteCursorX or not screen.paletteCursorY then return nil end
  local idx = (screen.paletteCursorY - 1) * cols + screen.paletteCursorX
  local off = screen.paletteOffset or 0
  local localIdx = idx - off
  if localIdx < 1 or localIdx > perPage then return nil end
  return localIdx
end

-- Draws the block palette in a 3-column grid.
function PaletteRenderer.drawBlocks(screen, panelX)
  local r = screen.map and screen.map.renderer
  if not r then return end
  local image = r.image
  local quads = r.quads
  local vw, vh = viewSize()
  drawBackdrop(panelX, vw, vh)

  local cols = BLOCK_COLS
  local rowPitch = BLOCK_SIZE + 8
  local visible = math.max(1, math.floor((vh - 18) / rowPitch))
  local perPage = visible * cols
  local list = screen.paletteList or {}
  local selPos = 0
  for i = 1, #list do
    if list[i] == screen.selectedBlock then selPos = i; break end
  end
  screen.paletteOffset = screen.paletteOffset or 0
  -- Keep the selected block visible, unless the palette focus cursor owns
  -- the scroll position.
  if selPos > 0 and not screen.paletteFocus then
    if selPos < screen.paletteOffset + 1 then
      screen.paletteOffset = math.max(0, selPos - 1)
    elseif selPos > screen.paletteOffset + perPage then
      screen.paletteOffset = math.max(0, selPos - perPage)
    end
  end

  for i = 1, perPage do
    local idx = screen.paletteOffset + i
    if idx > #list then break end
    local blockId = list[idx]
    local row = math.floor((i - 1) / cols)
    local col = (i - 1) % cols
    local px = panelX + 4 + col * (BLOCK_SIZE + BLOCK_GAP)
    local py = 10 + row * rowPitch
    local block = screen.tileset and screen.tileset.blocks[blockId + 1]
    if block then
      for r2 = 0, 3 do
        for c2 = 0, 3 do
          local ci = r2 * 4 + c2 + 1
          local tile = block[ci]
          local remap = r.aliasMap and r.aliasMap[blockId]
          if remap and remap[ci - 1] then tile = remap[ci - 1] end
          local quad = quads[tile]
          if quad then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(image, quad, px + c2 * TILE_PX, py + r2 * TILE_PX)
          end
        end
      end
      if blockId == screen.selectedBlock then
        love.graphics.setColor(1, 0, 0, 0.6)
        love.graphics.rectangle("line", px - 1, py - 1, BLOCK_SIZE + 2, BLOCK_SIZE + 2)
      end
      love.graphics.setColor(0.8, 0.8, 0.8, 1)
      screen.font.draw(tostring(blockId), px, py + BLOCK_SIZE)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  drawFocusCursor(screen, panelX, cursorLocalIndex(screen, cols, perPage),
    cols, rowPitch, BLOCK_SIZE, BLOCK_SIZE + 8)
end

-- Draws the sprite palette in a 2-column grid.
function PaletteRenderer.drawSprites(screen, panelX)
  local list = screen.spriteList
  if not list or #list == 0 then return end
  local sel = screen.selectedBlock or 1
  local vw, vh = viewSize()
  drawBackdrop(panelX, vw, vh)

  local cols = SPRITE_COLS
  local rowPitch = SPRITE_ROW
  local rows = math.max(2, math.floor((vh - 18) / rowPitch))
  local perPage = rows * cols
  screen.paletteOffset = screen.paletteOffset or 0
  -- Keep the selected sprite visible, unless the focus cursor owns scroll.
  if not screen.paletteFocus then
    local pageStart = math.floor((sel - 1) / perPage) * perPage
    if sel <= screen.paletteOffset or sel > screen.paletteOffset + perPage then
      screen.paletteOffset = pageStart
    end
  end

  for i = 1, perPage do
    local idx = screen.paletteOffset + i
    if idx > #list then break end
    local spriteId = list[idx]
    local row = math.floor((i - 1) / cols)
    local col = (i - 1) % cols
    local px = panelX + 4 + col * SPRITE_CELL
    local py = 10 + row * rowPitch

    if not screen._spriteRenderers then screen._spriteRenderers = {} end
    if not screen._spriteRenderers[spriteId] then
      local def = screen.data and screen.data.sprites[spriteId]
      if def then
        screen._spriteRenderers[spriteId] =
          require("src.render.SpriteRenderer").new(def, spriteId .. "_editor")
      end
    end
    local sr = screen._spriteRenderers[spriteId]
    if sr then
      love.graphics.setColor(1, 1, 1, 1)
      sr:draw(px, py + 4, 0, 0, "down", 0, false)
    else
      love.graphics.setColor(1, 0.4, 0.2, 0.7)
      love.graphics.rectangle("fill", px, py, 16, 16)
    end

    if idx == sel then
      love.graphics.setColor(1, 0, 0, 0.6)
      love.graphics.rectangle("line", px - 1, py - 1, 18, 18)
      love.graphics.setColor(1, 1, 1, 1)
    end

    -- Highlight the entity's current sprite while the sprite picker is open.
    if screen._spritePicker and screen._spritePicker.ent
       and screen._spritePicker.ent.sprite == spriteId then
      love.graphics.setColor(1, 1, 0, 0.5)
      love.graphics.rectangle("fill", px - 2, py - 2, 20, 20)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  drawFocusCursor(screen, panelX, cursorLocalIndex(screen, cols, perPage),
    cols, rowPitch, SPRITE_CELL, SPRITE_ROW)
end

-- Draws the appropriate palette for the current mode.
function PaletteRenderer.draw(screen, panelX)
  if screen.mode == MODES.ENT then
    PaletteRenderer.drawSprites(screen, panelX)
  else
    PaletteRenderer.drawBlocks(screen, panelX)
  end
end

return PaletteRenderer
