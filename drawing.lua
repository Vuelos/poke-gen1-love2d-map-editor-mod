-- Drawing routines for the map editor: map tiles, entity markers, cursor,
-- palette panel, mode bar, grid overlay, and help screen.

local MODES = { BLOCKS = 1, WARPS = 2, OBJECTS = 3, SIGNS = 4, ENCOUNTERS = 5, CONNECTIONS = 6 }
local MODE_NAMES = { "BLK", "WRP", "OBJ", "SGN", "ENC", "CON" }
local CELL_PX = 16
local TILE_PX = 8
local BLOCK_PX = 32
local PAL_BLOCK_SIZE = 32
local PAL_GAP = 4
local PAL_ROWS = 4
local PAL_COLS = 1
local PAL_VISIBLE = PAL_ROWS * PAL_COLS

local Drawing = {}

-- Draws the visible portion of the map tiles within the scroll viewport.
-- Iterates over tile-aligned regions and renders each tile quad from
-- the map renderer, applying block aliasing when present.
function Drawing.drawMap(screen)
  local r = screen.map.renderer
  if not r then return end
  local palW = screen.showPalette and 40 or 0
  local vw = 160 - palW
  local vh = 136
  local sx, sy = screen.scrollX, screen.scrollY

  local image = r.image
  local quads = r.quads
  local aliasMap = r.aliasMap
  local def = screen.def
  local ts = screen.tileset
  local blocks = def.blocks
  local bw = def.width

  local tx0 = math.max(0, math.floor(sx / 8))
  local ty0 = math.max(0, math.floor(sy / 8))
  local tx1 = math.min(bw * 4, math.ceil((sx + vw) / 8))
  local ty1 = math.min(def.height * 4, math.ceil((sy + vh) / 8))

  love.graphics.push()
  love.graphics.origin()
  love.graphics.setScissor(0, 8, vw, vh)
  for ty = ty0, ty1 - 1 do
    local by = math.floor(ty / 4)
    local tiy = ty % 4
    local rowOff = by * bw
    for tx = tx0, tx1 - 1 do
      local bId = blocks[rowOff + math.floor(tx / 4) + 1]
      local block = ts.blocks[(bId or 0) + 1]
      if block then
        local ci = tiy * 4 + (tx % 4)
        local tile = block[ci + 1]
        local remap = aliasMap and aliasMap[bId]
        if remap and remap[ci] then tile = remap[ci] end
        local quad = quads[tile]
        if quad then
          love.graphics.draw(image, quad, tx * 8 - sx, ty * 8 - sy)
        end
      end
    end
  end
  love.graphics.setScissor()
  love.graphics.pop()
end

-- Draws entity markers on the map.  Warps and signs render as coloured
-- circles; objects render the actual sprite via SpriteRenderer (falling
-- back to a coloured rectangle if the sprite cannot be loaded).  A yellow
-- highlight box is drawn around any entity currently being moved.
function Drawing.drawEntityMarkers(screen)
  local list = screen.mode == MODES.WARPS and screen.def.warps
    or screen.mode == MODES.OBJECTS and screen.def.objects
    or screen.def.signs
    or screen.mode == MODES.CONNECTIONS and screen.def.connections
  for _, ent in ipairs(list) do
    local ex = ent.x * CELL_PX - screen.scrollX
    local ey = ent.y * CELL_PX - screen.scrollY

    if screen.mode == MODES.OBJECTS then
      local spriteId = ent.sprite
      if spriteId and screen.data.sprites[spriteId] then
        if not screen._spriteRenderers then screen._spriteRenderers = {} end
        if not screen._spriteRenderers[spriteId] then
          local def = screen.data.sprites[spriteId]
          if def then
            screen._spriteRenderers[spriteId] =
              require("src.render.SpriteRenderer").new(def, spriteId .. "_editor")
          end
        end
        local sr = screen._spriteRenderers[spriteId]
        if sr then
          sr:draw(ent.x * 16, ent.y * 16, screen.scrollX, screen.scrollY, "down", 0, false)
        else
          love.graphics.setColor(1, 0.4, 0.2, 0.7)
          love.graphics.rectangle("fill", ex, ey, 16, 16)
          love.graphics.setColor(1, 1, 1, 0.8)
          love.graphics.rectangle("line", ex, ey, 16, 16)
        end
      else
        love.graphics.setColor(1, 0.4, 0.2, 0.7)
        love.graphics.rectangle("fill", ex, ey, 16, 16)
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.rectangle("line", ex, ey, 16, 16)
      end
    elseif screen.mode == MODES.CONNECTIONS then
      if ent and ent.width and ent.height then
        local color = { 0.2, 1, 0.4, 0.7 }
        local w = ent.width * 16
        local h = ent.height * 16
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", ex - w, ey - h, w * 2, h * 2)
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.rectangle("line", ex - w, ey - h, w * 2, h * 2)
      end
    else
    local color = screen.mode == MODES.WARPS and { 0.2, 0.6, 1, 0.7 } or { 0.2, 1, 0.4, 0.7 }
    local r = 10
    love.graphics.setColor(color); love.graphics.circle("fill", ex + r, ey + r, r)
    love.graphics.setColor(1, 1, 1, 0.8); love.graphics.circle("line", ex + r, ey + r, r)
  end

    if screen.entityMoving and screen.entityMovingTarget == ent then
      love.graphics.setColor(1, 1, 0, 0.9)
      love.graphics.rectangle("line", ex - 1, ey - 1, 18, 18)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draws the cursor rectangle (red fill + yellow outline) at the current
-- grid position.  In blocks mode the cursor spans one block (2 cells);
-- in entity modes it spans one cell.
function Drawing.drawCursor(screen)
  local bs = (screen.mode == MODES.BLOCKS) and 2 or screen.brushSize
  local ox = screen.cursorBx * CELL_PX - screen.scrollX
  local oy = screen.cursorBy * CELL_PX - screen.scrollY
  local sz = CELL_PX * bs
  love.graphics.setColor(1, 0, 0, 0.25); love.graphics.rectangle("fill", ox, oy, sz, sz)
  love.graphics.setColor(1, 1, 0, 0.8); love.graphics.rectangle("line", ox, oy, sz, sz)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draws the palette panel on the right side of the screen.
-- In OBJECTS mode, shows sprite previews; otherwise shows blocks.
function Drawing.drawPalette(screen, panelX)
  if screen.mode == MODES.OBJECTS then
    Drawing.drawSpritePalette(screen, panelX)
    return
  elseif screen.mode == MODES.ENCOUNTERS then return end
  local x, y = panelX + 4, 10
  local size = PAL_BLOCK_SIZE
  local r = screen.map.renderer
  local image = r.image
  local quads = r.quads

  love.graphics.setColor(0.1, 0.1, 0.1, 0.85)
  love.graphics.rectangle("fill", panelX, 0, 160 - panelX, 144)
  love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
  love.graphics.rectangle("line", panelX, 0, 160 - panelX, 144)

    for i = 1, PAL_VISIBLE do
        for p_i = 1, #screen.paletteList do
          if screen.paletteList[p_i] == screen.selectedBlock then
            local selPos = p_i
            if selPos < screen.paletteOffset + 1 then
              screen.paletteOffset = math.max(0, selPos - 1)
            elseif selPos > screen.paletteOffset + PAL_VISIBLE then
              screen.paletteOffset = math.max(0, selPos - PAL_VISIBLE)
            end
            break
          end
        end
        local idx = screen.paletteOffset + i
      if idx > #screen.paletteList then break end
      local blockId = screen.paletteList[idx]
      local block = screen.tileset.blocks[blockId + 1]
      if block then
        local py = y + (i - 1) * (size + PAL_GAP)
        local px = x
        for row = 0, 3 do
          for col = 0, 3 do
            local ci = row * 4 + col + 1
            local tile = block[ci]
            local remap = screen.map.renderer and screen.map.renderer.aliasMap and screen.map.renderer.aliasMap[blockId]
            if remap and remap[ci - 1] then tile = remap[ci - 1] end
            local quad = quads[tile]
            if quad then
              love.graphics.setColor(1, 1, 1, 1)
              love.graphics.draw(image, quad, px + col * TILE_PX, py + row * TILE_PX)
            end
          end
        end
        if blockId == screen.selectedBlock then
          love.graphics.setColor(1, 0, 0, 0.6)
          love.graphics.rectangle("line", px - 1, py - 1, size + 2, size + 2)
          love.graphics.setColor(1, 1, 1, 1)
        end
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        screen.font.draw(tostring(blockId), px + size + 4, py + 4)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
end

-- Draws the sprite palette panel in OBJECTS mode.
-- Shows sprite previews in 2 columns of 7 rows (14 visible at a time),
-- auto-scrolling to keep the selected sprite visible.
function Drawing.drawSpritePalette(screen, panelX)
  local list = screen.spriteList
  if not list or #list == 0 then return end
  local sel = screen.selectedBlock

  love.graphics.setColor(0.1, 0.1, 0.1, 0.85)
  love.graphics.rectangle("fill", panelX, 0, 160 - panelX, 144)
  love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
  love.graphics.rectangle("line", panelX, 0, 160 - panelX, 144)

  local rows = 7
  local cols = 2
  local perPage = rows * cols
  local pageStart = math.floor((sel - 1) / perPage) * perPage

  for i = 1, perPage do
    local idx = pageStart + i
    if idx > #list then break end
    local spriteId = list[idx]
    local row = math.floor((i - 1) / cols)
    local col = (i - 1) % cols
    local px = panelX + 4 + col * 18
    local py = 10 + row * 20

    -- Draw sprite preview
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

    -- Highlight selected
    if idx == sel then
      love.graphics.setColor(1, 0, 0, 0.6)
      love.graphics.rectangle("line", px - 1, py - 1, 18, 18)
      love.graphics.setColor(1, 1, 1, 1)
    end

  end
end

-- Draws a block-alignment grid overlay when showGrid is enabled.
-- Lines are drawn at block (32px) intervals within the map viewport.
function Drawing.drawGrid(screen)
  if not screen.showGrid then return end
  local palW = screen.showPalette and 40 or 0
  local vw = 160 - palW
  local vh = 136
  local sx, sy = screen.scrollX, screen.scrollY

  local bx0 = math.floor(sx / CELL_PX)
  local by0 = math.floor(sy / CELL_PX)
  local bx1 = math.ceil((sx + vw) / CELL_PX)
  local by1 = math.ceil((sy + vh) / CELL_PX)

  love.graphics.setColor(0.5, 0.5, 0.5, 0.35)
  for bx = bx0, bx1 do
    local lx = bx * CELL_PX - sx
    love.graphics.line(lx, 0, lx, vh)
  end
  for by = by0, by1 do
    local ly = by * CELL_PX - sy
    love.graphics.line(0, ly, vw, ly)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draws the mode indicator bar at the top of the screen, showing the
-- current editing mode (BLK/WRP/OBJ/SGN/ENC/CON) and cursor coordinates.
-- Also displays a "!" marker when the map has unsaved changes.
function Drawing.drawModeBar(screen)
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle("fill", 0, 0, 160, 8)

  for i = 1, 5 do
    local mx = (i - 1) * 32
    local label = MODE_NAMES[i]
    if i == screen.mode then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", mx, 0, 32, 8)
      love.graphics.setColor(0, 0, 0, 1)
    else
      love.graphics.setColor(0.6, 0.6, 0.6, 1)
    end
    screen.font.draw(label, mx + 4, 0)
  end
  love.graphics.setColor(1, 1, 1, 1)

  love.graphics.setColor(1, 1, 1, 1)
end

-- Draws the help overlay with controls reference, using the game's themed
-- box style (Font.drawBox) covering the area below the mode bar.
function Drawing.drawHelp(screen)
  local Font = require("src.render.Font")
  local vw, vh = 160, 144
  Font.drawBox(0, 1, 20, 17)
  love.graphics.setColor(0, 0, 0, 1)
  local lines = {
    "CONTROLS",
    "Arrows/WASD  Move",
    "Enter/Space  Edit",
    "1-6  BLK/WRP/OBJ/SGN/ENC/CON",
    "Q/E  Prev/next blk",
    "R  Revert block",
    "F  Copy cursor block",
    "G  Toggle grid",
    "Tab  Palette",
    "H  Toggle help",
    "CtrlZ Undo  CtrlY",
    "CtrlS Save  CtrlE",
    "Move: Arrows/Ent",
    "Esc  Close editor",
  }
  for i, line in ipairs(lines) do
    Font.draw(line, 8, 12 + (i - 1) * 9)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Drawing