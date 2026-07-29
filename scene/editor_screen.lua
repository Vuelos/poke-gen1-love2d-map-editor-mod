-- Map editor screen: main editing UI.  Delegates most logic to sub-modules
-- (map_ops, camera, events, new_map, save, drawing, entity_editor).

local Save = require("mods.map_editor.func.save")
local Drawing = require("mods.map_editor.drawing")
local EntityEditor = require("mods.map_editor.scene.entity_editor")
local Undo = require("mods.map_editor.func.undo")
local Fill = require("mods.map_editor.func.fill")
local Common = require("mods.map_editor.func.common")
local TileRenderer = require("src.render.TileRenderer")
local PaletteFX = require("src.render.PaletteFX")
local FieldDefaults = require("src.world.FieldDefaults")

local MODES = Common.MODES
local BLOCK_PX = Common.BLOCK_PX

local EditorScreen = {}

-- Mixin methods from extracted sub-modules
local function mixin(t, src) for k, v in pairs(src) do t[k] = v end end
mixin(EditorScreen, require("mods.map_editor.func.map_ops"))
mixin(EditorScreen, require("mods.map_editor.func.camera"))
mixin(EditorScreen, require("mods.map_editor.func.events"))
mixin(EditorScreen, require("mods.map_editor.func.new_map"))

-- Builds a new EditorScreen for the given mod, game, and mapId.
-- Loads tileset, renderer, palette; initialises cursor, scroll, undo stack,
-- and takes an original-state snapshot for change tracking.
-- Returns nil if the map or tileset cannot be loaded.
function EditorScreen.new(mod, game, mapId)
  local data = game.data
  local def = data.maps[mapId]
  if not def then return nil end
  local tileset = data.tilesets[def.tileset]
  if not tileset then return nil end

  local MapLoader = require("src.world.MapLoader")
  local map = MapLoader.load(data, mapId)
  if not map or not map.renderer then return nil end

  local self = {
    mod = mod, game = game, data = data,
    mapId = mapId, def = def, tileset = tileset,
    map = map,
    mode = MODES.BLOCKS,
    cursorBx = 0, cursorBy = 0,
    scrollX = 0, scrollY = 0,
    selectedBlock = 1,
    paletteOffset = 0,
    showPalette = true,
    showHelp = false,
    showGrid = false,
    mapChanged = false,
    undo = Undo.new(),
    originalBlocks = nil,
    originalWidth = nil,
    originalHeight = nil,
    font = mod.ui.Font,
    isOpaque = true,
    mapW = def.width * BLOCK_PX, mapH = def.height * BLOCK_PX,
    paletteColors = nil,
    brushSize = 1,
    sgbPalettes = function(self)
      if PaletteFX.usesGbcPack() then return {} end
      local ow = self.game.overworld
      return ow and ow.sgbPalettes and ow:sgbPalettes(self.game) or nil
    end,
  }

  TileRenderer.tick(0)

  local palettes = FieldDefaults.field(data, "palettes")
  local palName = def.palette
  if not palName then palName = palettes.byMap and palettes.byMap[mapId] end
  if not palName then palName = palettes.byTileset and palettes.byTileset[def.tileset] end
  if not palName then
    for _, row in ipairs(palettes.byPrefix or {}) do
      if row.prefix and mapId:find(row.prefix, 1, true) == 1 then
        palName = row.palette; break
      end
    end
  end
  if not palName then palName = palettes.default end
  self.paletteColors = PaletteFX.pal(data, palName)

  setmetatable(self, { __index = EditorScreen })
  self:storeOriginal()
  return self
end

-- Reloads the map renderer from data and refreshes the original snapshot.
function EditorScreen:reloadMap()
  local MapLoader = require("src.world.MapLoader")
  MapLoader.invalidate(self.mapId)
  self.map = MapLoader.load(self.data, self.mapId)
  TileRenderer.tick(0)
  self:storeOriginal()
end

-- Called when the screen is entered: applies any saved patches, rebuilds
-- the renderer, and hooks mouse events.
function EditorScreen:enter()
  local patches = Save.getPatches(self.mod)
  local patch = patches[self.mapId]
  if patch then
    for key, value in pairs(patch) do
      if key == "blocks" then
        for i, v in ipairs(value) do
          if self.def.blocks[i] ~= nil then self.def.blocks[i] = v end
        end
      elseif key ~= "id" then
        self.def[key] = value
      end
    end
  end
  if self.def.connections then self.def.connections = Save.applyConnectionPatches({ [self.mapId] = self.def.connections }, self.data) end
  -- Inject custom text defs into game data so they resolve correctly
  if self.def.textDefs and self.data then
    for _, td in ipairs(self.def.textDefs) do
      if not self.data.text_pointers[self.mapId] then
        self.data.text_pointers[self.mapId] = {}
      end
      self.data.text_pointers[self.mapId][td.const] = { text = td.key }
      self.data.text[td.key] = td.text
    end
  end
  -- Apply encounter patches
  local encPatches = Save.getEncounterPatches(self.mod)
  local encPatch = encPatches and encPatches[self.mapId]
  if encPatch and self.data then
    self.data.encounters = self.data.encounters or {}
    self.data.encounters[self.mapId] = encPatch
  end
  self.map.renderer:rebuild()
  self:hookMouse()
end

  -- Called when the screen is exited: unhooks mouse events.
  function EditorScreen:exit()
    self:unhookMouse()
  end

-- Builds a patch of only the changed fields and saves it via the Save
-- module.  Reloads the map to reflect the persisted state.
function EditorScreen:savePatches()
  local patch = Save.buildPatch(self.def, {
    blocks = self.originalBlocks, warps = self.originalWarps,
    objects = self.originalObjects, signs = self.originalSigns,
    borderBlock = self.originalBorder, width = self.originalWidth, height = self.originalHeight,
    textDefs = self.originalTextDefs,
  })
  Save.savePatch(self.mod, self.mapId, patch)
  local invalidated = false
  local world = self.mod.world
  if world and world.invalidateMap then
    invalidated = world:invalidateMap(self.mapId) ~= nil
  end
  if not invalidated then
    local MapLoader = require("src.world.MapLoader")
    MapLoader.invalidate(self.mapId)
  end
  self.map = require("src.world.MapLoader").load(self.data, self.mapId)
  TileRenderer.tick(0)
  -- Re-inject custom text defs into the fresh game data after reload
  if self.def.textDefs and self.data then
    for _, td in ipairs(self.def.textDefs) do
      if not self.data.text_pointers[self.mapId] then
        self.data.text_pointers[self.mapId] = {}
      end
      self.data.text_pointers[self.mapId][td.const] = { text = td.key }
      self.data.text[td.key] = td.text
    end
  end
  -- Save encounter patch
  local currentEnc = self.data and self.data.encounters and self.data.encounters[self.mapId]
  if not Common.tablesEqual(currentEnc, self.originalEncounters) then
    if currentEnc then
      Save.saveEncounterPatch(self.mod, self.mapId, Common.deepCopy(currentEnc))
    else
      Save.removeEncounterPatch(self.mod, self.mapId)
    end
  end
  self:storeOriginal(); self.mapChanged = false
  self.map.renderer:rebuild()
end

-- Exports the current patch as a Lua file on disk, suitable for use as
-- a mod override script.
function EditorScreen:exportPatches()
  local patch = Save.buildPatch(self.def, {
    blocks = self.originalBlocks, warps = self.originalWarps,
    objects = self.originalObjects, signs = self.originalSigns,
    borderBlock = self.originalBorder, width = self.originalWidth, height = self.originalHeight,
    textDefs = self.originalTextDefs,
  })
  local lua = {"-- Map editor export for " .. self.mapId, "return {"}
  for key, value in pairs(patch) do
    if key == "blocks" then
      lua[#lua + 1] = "  blocks = {"
      local parts = {}
      for _, v in ipairs(value) do parts[#parts + 1] = tostring(v) end
      lua[#lua + 1] = "    " .. table.concat(parts, ", "); lua[#lua + 1] = "  },"
    elseif type(value) == "table" then
      local ok, enc = pcall(require("src.mods.Merge").encode, value)
      lua[#lua + 1] = "  " .. key .. " = " .. (ok and enc or "{}") .. ","
    else
      lua[#lua + 1] = "  " .. key .. " = " .. tostring(value) .. ","
    end
  end
  lua[#lua + 1] = "}"
  local text = table.concat(lua, "\n")
  local path = Save.writeFile(self.mapId, text)
  self.mod.log:info("Exported %s patches to %s", self.mapId, path)
end

-- Called every frame to keep the tile renderer and scroll clamp updated.
function EditorScreen:update()
  TileRenderer.tick(0)
  self:clampScroll()
end

-- Renders the editor: map tiles, grid, entity markers, cursor, palette,
-- mode bar, and help overlay.
function EditorScreen:draw()
  local renderer = self.map.renderer
  if not renderer then
    love.graphics.setColor(0, 0, 0, 1); love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
    self.font.draw("MAP EDITOR", 40, 30)
    self.font.draw(self.mapId, 40, 50); return
  end

  local vw, vh = 160, 144
  local palW = self.showPalette and 40 or 0
  local mapViewW = vw - palW

  love.graphics.setScissor(0, 8, mapViewW, 136)
  Drawing.drawMap(self)
  love.graphics.setScissor(0, 8, mapViewW, 136)
  Drawing.drawGrid(self)

  if self.mode >= MODES.WARPS and self.mode <= MODES.CONNECTIONS then
    Drawing.drawEntityMarkers(self)
  end
  Drawing.drawCursor(self)

  -- New map preview rectangle
  if self._newMapState and self._newMapState.showPreview then
    local s = self._newMapState
    local bw = self.def.width * 32
    local bh = self.def.height * 32
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
    love.graphics.setColor(0, 1, 0, 0.35)
    love.graphics.rectangle("fill", px - self.scrollX, py - self.scrollY, pw, ph)
    love.graphics.setColor(0, 1, 0, 0.8)
    love.graphics.rectangle("line", px - self.scrollX, py - self.scrollY, pw, ph)
    love.graphics.setColor(1, 1, 1, 1)
  end

  love.graphics.setScissor()

  if self.showPalette then Drawing.drawPalette(self, mapViewW) end

  Drawing.drawModeBar(self)
  -- Coordinates at bottom-left
  love.graphics.setColor(0.6, 0.6, 0.6, 1)
  self.font.draw(("%d,%d"):format(self.cursorBx, self.cursorBy), 0, 136)
  if self.mapChanged then
    love.graphics.setColor(1, 0.8, 0.2, 1)
    self.font.draw("!", 50, 136)
  end
  love.graphics.setColor(1, 1, 1, 1)

  if self._newMapState and self._newMapState.editField then self:drawNewMapDialog() end

  if self.showHelp then
    Drawing.drawHelp(self)
  end
end

return EditorScreen