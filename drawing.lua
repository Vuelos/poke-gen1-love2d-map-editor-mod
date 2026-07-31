-- Drawing routines for the map editor: map tiles, entity markers, cursor,
-- palette panel, mode bar, grid overlay, and help screen.

local Common = require("mods.map_editor.func.common")
local MODES = Common.MODES
local MODE_NAMES = { "MAP", "ENT", "ENC" }
local CELL_PX = 16
local TILE_PX = 8
local BLOCK_PX = 32
local PAL_BLOCK_SIZE = 32
local PAL_GAP = 4

local Drawing = {}

-- Live UI surface size for this frame.  The editor runs fullscreen (its
-- own uiSize() fills the window); sub-menus on the stack revert the canvas
-- to the classic 160x144 GB screen, so every metric must be derived from the
-- actual canvas rather than hardcoded.
local function viewSize()
  return require("src.render.Renderer"):uiSize()
end

-- Palette column width in GB pixels.
local PAL_W = Common.PAL_W

-- Width/height of the map viewport below the mode bar for this screen.
function Drawing.viewport(screen)
  local vw, vh = viewSize()
  local palW = screen.showPalette and screen.mode ~= MODES.ENC and PAL_W or 0
  return vw - palW, vh - 8
end

-- Draws the visible portion of one map's block body at a world offset
-- (0,0 for the edited map), clipped to its own rect.  Shared by the edited
-- map and, in MAP mode, the connected maps laid out around it so seams can
-- be edited straight across.
local function drawMapTiles(screen, r, def, ts, ox, oy, vw, vh)
  if not r or not ts then return end
  local sx, sy = screen.scrollX, screen.scrollY
  local image = r.image
  local quads = r.quads
  local aliasMap = r.aliasMap
  local blocks = def.blocks
  local bw, bh = def.width, def.height

  local tx0 = math.max(0, math.floor(sx / 8) - ox / 8)
  local ty0 = math.max(0, math.floor(sy / 8) - oy / 8)
  local tx1 = math.min(bw * 4, math.ceil((sx + vw) / 8) - ox / 8)
  local ty1 = math.min(bh * 4, math.ceil((sy + vh) / 8) - oy / 8)

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
          love.graphics.draw(image, quad, ox + tx * 8 - sx, oy + ty * 8 - sy)
        end
      end
    end
  end
end

-- Draws the visible map tiles within the scroll viewport: the connected
-- maps first (MAP mode), then the edited map on top.  Iterates over
-- tile-aligned regions and renders each tile quad from the map renderer,
-- applying block aliasing when present.
function Drawing.drawMap(screen)
  local vw, vh = Drawing.viewport(screen)

  love.graphics.push()
  love.graphics.origin()
  love.graphics.setScissor(0, 8, vw, vh)
  if screen.mode == MODES.MAP then
    for _, nb in ipairs(screen.neighbors or {}) do
      drawMapTiles(screen, nb.map and nb.map.renderer, nb.def, nb.tileset,
                   nb.ox, nb.oy, vw, vh)
    end
  end
  drawMapTiles(screen, screen.map.renderer, screen.def, screen.tileset,
               0, 0, vw, vh)
  love.graphics.setScissor()
  love.graphics.pop()
end

-- Draws entity markers on the map in ENT mode: warps and signs render as
-- coloured circles, objects render the actual sprite via SpriteRenderer
-- (falling back to a coloured rectangle if the sprite cannot be loaded),
-- and connection silhouettes are drawn underneath.  A yellow highlight box
-- is drawn around any entity currently being moved.
function Drawing.drawEntityMarkers(screen)
  if screen.mode ~= MODES.ENT then return end
  Drawing.drawConnectionSilhouettes(screen)

  local function drawObject(ent)
    local ex = ent.x * CELL_PX - screen.scrollX
    local ey = ent.y * CELL_PX - screen.scrollY
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
    if screen.entityMoving and screen.entityMovingTarget == ent then
      love.graphics.setColor(1, 1, 0, 0.9)
      love.graphics.rectangle("line", ex - 1, ey - 1, 18, 18)
    end
  end

  local function drawCircle(ent, color)
    local ex = ent.x * CELL_PX - screen.scrollX
    local ey = ent.y * CELL_PX - screen.scrollY
    local r = 10
    love.graphics.setColor(color); love.graphics.circle("fill", ex + r, ey + r, r)
    love.graphics.setColor(1, 1, 1, 0.8); love.graphics.circle("line", ex + r, ey + r, r)
    if screen.entityMoving and screen.entityMovingTarget == ent then
      love.graphics.setColor(1, 1, 0, 0.9)
      love.graphics.rectangle("line", ex - 1, ey - 1, 18, 18)
    end
  end

  for _, ent in ipairs(screen.def.warps or {}) do
    drawCircle(ent, { 0.2, 0.6, 1, 0.7 })
  end
  for _, ent in ipairs(screen.def.objects or {}) do
    drawObject(ent)
  end
  for _, ent in ipairs(screen.def.signs or {}) do
    drawCircle(ent, { 0.2, 1, 0.4, 0.7 })
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draws all map connections as green semi-transparent silhouettes at their
-- correct map-edge positions.  Each connection is labelled with its direction
-- and target map.  The silhouette spans the full strip width/height (map
-- width for N/S, map height for W/E) and is 2 blocks deep.
function Drawing.drawConnectionSilhouettes(screen)
  local conns = screen.def.connections or {}
  if not next(conns) then return end
  local def = screen.def
  local mw = def.width * 32
  local mh = def.height * 32
  local sx, sy = screen.scrollX, screen.scrollY
  local data = screen.data

  for dir, conn in pairs(conns) do
    local off = (conn.offset or 0) * 32
    local destDef = data and data.maps and data.maps[conn.map]

    local rx, ry, rw, rh

    if dir == "north" then
      rw = destDef and destDef.width * 32 or mw
      rh = 64
      rx = off
      ry = -rh
    elseif dir == "south" then
      rw = destDef and destDef.width * 32 or mw
      rh = 64
      rx = off
      ry = mh
    elseif dir == "west" then
      rw = 64
      rh = destDef and destDef.height * 32 or mh
      rx = -rw
      ry = off
    elseif dir == "east" then
      rw = 64
      rh = destDef and destDef.height * 32 or mh
      rx = mw
      ry = off
    end

    local dx = rx - sx
    local dy = ry - sy

    love.graphics.setColor(0.2, 1, 0.4, 0.35)
    love.graphics.rectangle("fill", dx, dy, rw, rh)
    love.graphics.setColor(0.2, 1, 0.4, 0.8)
    love.graphics.rectangle("line", dx, dy, rw, rh)
    love.graphics.setColor(1, 1, 1, 1)
    screen.font.draw(dir:upper() .. " " .. (conn.map or ""), dx + 2, dy + 2)

    if screen._selectedDir == dir then
      love.graphics.setColor(1, 1, 0, 0.9)
      love.graphics.rectangle("line", dx - 1, dy - 1, rw + 2, rh + 2)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draws the cursor rectangle (red fill + yellow outline) at the current
-- grid position.  In blocks mode the cursor spans one block (2 cells);
-- in entity modes it spans one cell.
function Drawing.drawCursor(screen)
  local bs = (screen.mode == MODES.MAP) and 2 or screen.brushSize
  local ox = screen.cursorBx * CELL_PX - screen.scrollX
  local oy = screen.cursorBy * CELL_PX - screen.scrollY
  local sz = CELL_PX * bs
  love.graphics.setColor(1, 0, 0, 0.25); love.graphics.rectangle("fill", ox, oy, sz, sz)
  love.graphics.setColor(1, 1, 0, 0.8); love.graphics.rectangle("line", ox, oy, sz, sz)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draws the palette panel on the right side of the screen.
-- In ENT mode, shows sprite previews; otherwise shows blocks.
function Drawing.drawPalette(screen, panelX)
  if screen.mode == MODES.ENT then
    Drawing.drawSpritePalette(screen, panelX)
    return
  elseif screen.mode == MODES.ENC then return end
  local x, y = panelX + 4, 10
  local size = PAL_BLOCK_SIZE
  local r = screen.map.renderer
  local image = r.image
  local quads = r.quads
  local vw, vh = viewSize()

  love.graphics.setColor(0.1, 0.1, 0.1, 0.85)
  love.graphics.rectangle("fill", panelX, 0, vw - panelX, vh)
  love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
  love.graphics.rectangle("line", panelX, 0, vw - panelX, vh)

    local cols = 2
    local rowPitch = size + 8
    local visible = math.max(1, math.floor((vh - 18) / rowPitch))
    local perPage = visible * cols
    local selPos = 0
    for p_i = 1, #screen.paletteList do
      if screen.paletteList[p_i] == screen.selectedBlock then
        selPos = p_i
        break
      end
    end
    if selPos > 0 then
      if selPos < screen.paletteOffset + 1 then
        screen.paletteOffset = math.max(0, selPos - 1)
      elseif selPos > screen.paletteOffset + perPage then
        screen.paletteOffset = math.max(0, selPos - perPage)
      end
    end
    for i = 1, perPage do
      local idx = screen.paletteOffset + i
      if idx > #screen.paletteList then break end
      local blockId = screen.paletteList[idx]
      local row = math.floor((i - 1) / cols)
      local col = (i - 1) % cols
      local px = x + col * (size + PAL_GAP)
      local py = y + row * rowPitch
      local block = screen.tileset.blocks[blockId + 1]
      if block then
        for r2 = 0, 3 do
          for c2 = 0, 3 do
            local ci = r2 * 4 + c2 + 1
            local tile = block[ci]
            local remap = screen.map.renderer and screen.map.renderer.aliasMap and screen.map.renderer.aliasMap[blockId]
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
          love.graphics.rectangle("line", px - 1, py - 1, size + 2, size + 2)
          love.graphics.setColor(1, 1, 1, 1)
        end
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        screen.font.draw(tostring(blockId), px, py + size)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
end

-- Draws the sprite palette panel in ENT mode.
-- Shows sprite previews in 4 columns, auto-scrolling to keep the selected
-- sprite visible.
function Drawing.drawSpritePalette(screen, panelX)
  local list = screen.spriteList
  if not list or #list == 0 then return end
  local sel = screen.selectedBlock
  local vw, vh = viewSize()

  love.graphics.setColor(0.1, 0.1, 0.1, 0.85)
  love.graphics.rectangle("fill", panelX, 0, vw - panelX, vh)
  love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
  love.graphics.rectangle("line", panelX, 0, vw - panelX, vh)

  local rows = math.max(4, math.floor((vh - 18) / 20))
  local cols = 4
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
  local vw, vh = Drawing.viewport(screen)
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
-- current editing mode (MAP/ENT/ENC).  Also displays a "!" marker when
-- the map has unsaved changes.
function Drawing.drawModeBar(screen)
  local vw = viewSize()
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle("fill", 0, 0, vw, 8)

  local slotW = 53
  for i = 1, 3 do
    local mx = (i - 1) * slotW
    local label = MODE_NAMES[i]
    if i == screen.mode then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", mx, 0, slotW, 8)
      love.graphics.setColor(0, 0, 0, 1)
    else
      love.graphics.setColor(0.25, 0.25, 0.25, 1)
      love.graphics.rectangle("fill", mx, 0, slotW, 8)
      love.graphics.setColor(0.85, 0.85, 0.85, 1)
    end
    screen.font.draw(label, mx + 2, 0)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draws the help overlay with controls reference, using the game's themed
-- box style (Font.drawBox) covering the area below the mode bar.
function Drawing.drawHelp(screen)
  local Font = require("src.render.Font")
  local vw, vh = viewSize()
  Font.drawBox(0, 1, math.floor(vw / 8), math.floor(vh / 8))
  love.graphics.setColor(0, 0, 0, 1)
  local lines = {
    "CONTROLS",
    "Arrows/WASD  Move",
    "Enter/Space  Edit/Add",
    "1-3  MAP/ENT/ENC",
    "Q/E  Prev/next ent",
    "R  Revert block",
    "F  Copy cursor block",
    "G  Toggle grid",
    "Tab  Palette",
    "H  Toggle help",
    "CtrlZ Undo  CtrlY",
    "CtrlS Save  CtrlE",
    "Move: Arrows/Ent",
    "ENT: all entities",
    "Esc  Close editor",
  }
  for i, line in ipairs(lines) do
    Font.draw(line, 8, 12 + (i - 1) * 9)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Drawing