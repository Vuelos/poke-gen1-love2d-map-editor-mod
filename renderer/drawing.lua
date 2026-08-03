-- Drawing routines for the map editor: map tiles, entity markers, cursor,
-- palette panel, mode bar, grid overlay, and help screen.

local Common = require("mods.map_editor.func.common")
local MODES = Common.MODES
local MODE_NAMES = { "MAP", "ENT", "ENC" }
local CELL_PX = 16
local BLOCK_PX = 32
local PaletteRenderer = require("mods.map_editor.renderer.palette")

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
    local isSelectedSprite = screen._spritePicker and screen._spritePicker.ent == ent and screen._spritePicker.kind == "object"
    
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
        if isSelectedSprite then
          love.graphics.setColor(1, 1, 0, 0.9)
          love.graphics.rectangle("line", ex - 2, ey - 2, 20, 20)
        end
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
-- and target map name.  The silhouette spans the map's full edge (map
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
      rw = mw
      rh = 64
      rx = off
      ry = -rh
    elseif dir == "south" then
      rw = mw
      rh = 64
      rx = off
      ry = mh
    elseif dir == "west" then
      rw = 64
      rh = mh
      rx = -rw
      ry = off
    elseif dir == "east" then
      rw = 64
      rh = mh
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
    screen.font.draw(dir:upper() .. " " .. (destDef and destDef.name or conn.map or ""), dx + 2, dy + 2)

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

-- Draws the palette panel on the right side of the screen.  Delegates to
-- the palette renderer (blocks in a 3-column grid, sprites in 2 columns,
-- plus the focus cursor when the palette has input focus).
function Drawing.drawPalette(screen, panelX)
  if screen.mode == MODES.ENC then return end
  PaletteRenderer.draw(screen, panelX)
end


-- Renders the full map editor scene.  Calls all sub-drawing
-- functions in the correct order: backdrop, map, grid, entities,
-- cursor, palette, mode bar, coordinates, and help overlay.
function Drawing.drawMapEditor(screen)
  local renderer = screen.map.renderer
  local vw, vh = viewSize()
  if not renderer then
    Drawing.drawError(screen)
    return
  end

  screen.viewW, screen.viewH = vw, vh
  local palW = screen.showPalette and screen.mode ~= MODES.ENC and PAL_W or 0
  local mapViewW = vw - palW
  local viewH = vh - 8

  Drawing.drawBackdrop(screen)

  love.graphics.setScissor(0, 8, mapViewW, viewH)
  Drawing.drawMap(screen)
  love.graphics.setScissor(0, 8, mapViewW, viewH)
  Drawing.drawGrid(screen)

  if screen.mode == MODES.ENT then
    Drawing.drawEntityMarkers(screen)
  end
  -- The map cursor stays visible at all times; TAB only moves input focus
  -- to the palette cursor, it never hides the map cursor.
  Drawing.drawCursor(screen)

  Drawing.drawNewMapPreview(screen)

  love.graphics.setScissor()

  if screen.showPalette then Drawing.drawPalette(screen, mapViewW) end

  Drawing.drawModeBar(screen)
  Drawing.drawCoordinates(screen)

  if screen._newMapState and screen._newMapState.editField then screen:drawNewMapDialog() end

  if screen.showHelp then
    Drawing.drawHelp(screen)
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
    "Tab  Focus palette",
    "WASD  Palette cursor",
    "H  Toggle help",
    "CtrlZ Undo / CtrlY Redo",
    "CtrlS Save on current save",
    "CtrlE Export to mod folder",
    "CtrlI Import from mod folder",
    "Esc  Close editor",
  }
  for i, line in ipairs(lines) do
    Font.draw(line, 8, 12 + (i - 1) * 9)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draws an error fallback when the map renderer is unavailable.
function Drawing.drawError(screen)
  local vw, vh = viewSize()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, vw, vh)
  love.graphics.setColor(1, 1, 1, 1)
  screen.font.draw("MAP EDITOR", 40, 30)
  screen.font.draw(screen.mapId, 40, 50)
end

-- Draws an opaque black backdrop covering the full canvas.
function Drawing.drawBackdrop(screen)
  local vw, vh = viewSize()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, vw, vh)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draws a green semi-transparent preview rectangle for a new map
-- being laid out, with a green border.  The preview is positioned
-- relative to the edited map's bounds and offset by the current
-- scroll position.
function Drawing.drawNewMapPreview(screen)
  local s = screen._newMapState
  if not s or not s.showPreview then return end
  local bw = screen.def.width * 32
  local bh = screen.def.height * 32
  local pw = s.width * 32
  local ph = s.height * 32
  local px, py
  if s.dir == "N" then
    px = (bw - pw) / 2; py = -ph
  elseif s.dir == "S" then
    px = (bw - pw) / 2; py = bh
  elseif s.dir == "E" then
    px = bw; py = (bh - ph) / 2
  else
    px = -pw; py = (bh - ph) / 2
  end
  local sx, sy = screen.scrollX, screen.scrollY
  love.graphics.setColor(0, 1, 0, 0.35)
  love.graphics.rectangle("fill", px - sx, py - sy, pw, ph)
  love.graphics.setColor(0, 1, 0, 0.8)
  love.graphics.rectangle("line", px - sx, py - sy, pw, ph)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draws the cursor coordinates and an unsaved-changes marker at
-- the bottom-left of the screen.
function Drawing.drawCoordinates(screen)
  local vw, vh = viewSize()
  love.graphics.setColor(0.6, 0.6, 0.6, 1)
  screen.font.draw(("%d,%d"):format(screen.cursorBx, screen.cursorBy), 0, vh)
  if screen.mapChanged then
    love.graphics.setColor(1, 0.8, 0.2, 1)
    screen.font.draw("!", 50, vh)
  end
  love.graphics.setColor(1, 1, 1, 1)
end
return Drawing
